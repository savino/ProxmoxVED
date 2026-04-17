#!/usr/bin/env bash
# shellcheck disable=SC2034
set -Eeuo pipefail

# encrypt-lxc-dataset.sh
#
# Usage:
#   ./encrypt-lxc-dataset.sh <CTID> <PASS_FILE> [VOLID] [--yes]
#
# Examples:
#   ./encrypt-lxc-dataset.sh 101 /root/zfs-pass/ct101.pass
#   ./encrypt-lxc-dataset.sh 101 /root/zfs-pass/ct101.pass zfspool:subvol-101-disk-1
#   ./encrypt-lxc-dataset.sh 101 /root/zfs-pass/ct101.pass --yes
#
# What it does:
# - detects private datasets associated with the CT (eligible rootfs + mpX)
# - converts all eligible private zfspool/subvol-* datasets by default
# - supports optional selection of a single target via Proxmox VOLID
# - prints a preflight recap and requires explicit confirmation
# - stops the container and waits until the state is actually stopped
# - creates the new encrypted dataset using zfs recv encryption properties
# - updates rootfs/mpX only for successfully converted targets
# - keeps source datasets intact for manual rollback
#
# Behavior Details:
# - Default target set: all CT entries in `rootfs` and `mpX` that are private `subvol-*` on `zfspool` storage
# - Exclusions: bind mounts, non-storage mounts, non-`subvol-*` entries, non-`zfspool` storages,
#   already encrypted datasets, or targets with existing destination dataset
# - Preflight recap: prints detected targets, skipped reasons, destination mapping, and config updates
# - Confirmation: requires interactive confirmation (y/yes) unless --yes is supplied
# - Safety measures:
#   - Stops container with graceful timeout and forced fallback
#   - Creates config backup under /root/<CTID>.conf.bak.<timestamp>
#   - Creates per-target rollback snapshots
#   - Updates only converted rootfs/mpX entries
#
# Notes:
# - PASS_FILE is a text file containing the passphrase
# - keep PASS_FILE outside encrypted datasets
# - shutdown timeout: 3 minutes
# - already encrypted or ineligible datasets are skipped
# - use --yes for non-interactive execution

YW=$'\033[33m'
# The following color variables are intentionally defined for consistency with
# repository style headers. Some may be unused in this script but kept for
# readability and parity with other scripts.
BL=$'\033[36m'
HA=$'\033[1;34m'
RD=$'\033[01;31m'
BGN=$'\033[4;92m'
DGN=$'\033[32m'
GN=$'\033[1;92m'
CL=$'\033[m'
BFR=$'\r\033[K'
HOLD='-'
TAB='  '
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="${TAB}💡${TAB}${CL}"

function msg_info() {
  local msg="$1"
  printf ' %s %b...\n' "$HOLD" "${YW}${msg}"
}

function msg_ok() {
  local msg="$1"
  printf '%b %b%s%b\n' "${BFR}" "${CM}" "${GN}${msg}" "${CL}"
}

function msg_error() {
  local msg="$1"
  printf '%b %b%s%b\n' "${BFR}" "${CROSS}" "${RD}${msg}" "${CL}"
}

CTID="${1:?missing CTID}"
PASS_FILE="${2:?missing PASS_FILE}"
TARGET_VOLID=""
AUTO_YES=0

if [ "$#" -gt 4 ]; then
  echo "ERROR: too many arguments" >&2
  exit 1
fi

for arg in "${@:3}"; do
  case "$arg" in
    --yes)
      AUTO_YES=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  encrypt-lxc-dataset.sh <CTID> <PASS_FILE> [VOLID] [--yes]

Examples:
  encrypt-lxc-dataset.sh 101 /root/zfs-pass/ct101.pass
  encrypt-lxc-dataset.sh 101 /root/zfs-pass/ct101.pass zfspool:subvol-101-disk-1
  encrypt-lxc-dataset.sh 101 /root/zfs-pass/ct101.pass --yes
EOF
      exit 0
      ;;
    *)
      if [ -z "$TARGET_VOLID" ]; then
        TARGET_VOLID="$arg"
      else
        echo "ERROR: unexpected argument: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

CFG="/etc/pve/lxc/${CTID}.conf"
TS="$(date +%Y%m%d-%H%M%S)"
SNAP_PREFIX="pre-encrypt-${TS}"
CFG_BAK="/root/${CTID}.conf.bak.${TS}"
PROP_NS="custom.proxmox"

SHUTDOWN_TIMEOUT=180
GRACEFUL_WAIT_TIMEOUT=180
FORCE_WAIT_TIMEOUT=60

declare -a TARGET_KEYS=()
declare -a TARGET_VOLIDS=()
declare -a TARGET_REST_OPTS=()
declare -a TARGET_STORAGES=()
declare -a TARGET_VOLNAMES=()
declare -a TARGET_SRC_DATASETS=()
declare -a TARGET_DST_DATASETS=()
declare -a TARGET_DST_VOLIDS=()
declare -a TARGET_PCT_OPTIONS=()
declare -a TARGET_PCT_VALUES=()
declare -a TARGET_SNAPS=()
declare -a TARGET_SKIP_REASONS=()
declare -a TARGET_CONVERTED=()
declare -a TARGET_FINAL_SKIPPED=()

cleanup_on_error() {
  local ec=$?
  if [ "$ec" -ne 0 ]; then
    echo "ERROR: script aborted with exit code $ec" >&2
    echo "Possible rollback targets:" >&2
    echo "  Config backup: $CFG_BAK" >&2
    if [ "${#TARGET_SNAPS[@]}" -eq 0 ]; then
      echo "  Snapshot: unknown" >&2
    else
      for i in "${!TARGET_SNAPS[@]}"; do
        echo "  Snapshot: ${TARGET_SRC_DATASETS[$i]}@${TARGET_SNAPS[$i]}" >&2
      done
    fi
    if [ "${#TARGET_DST_DATASETS[@]}" -eq 0 ]; then
      echo "  Destination dataset: unknown" >&2
    else
      for dst in "${TARGET_DST_DATASETS[@]}"; do
        echo "  Destination dataset: ${dst}" >&2
      done
    fi
  fi
  exit "$ec"
}
trap cleanup_on_error EXIT

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

trim_leading_space() {
  local value="$1"
  printf '%s' "$value" | sed 's/^[[:space:]]*//'
}

get_storage_type() {
  local storage="$1"
  pvesm status | awk -v s="$storage" '$1==s {print $2; exit}'
}

get_storage_pool() {
  local storage="$1"
  pvesm config "$storage" 2>/dev/null | awk '$1=="pool" {print $2; exit}'
}

resolve_source_dataset() {
  local storage="$1"
  local volname="$2"
  local volid="$3"
  local pool=""
  local dataset=""
  local dataset_path=""

  pool="$(get_storage_pool "$storage")"
  if [ -n "$pool" ]; then
    dataset="${pool}/${volname}"
    if zfs list -H "$dataset" >/dev/null 2>&1; then
      echo "$dataset"
      return 0
    fi
  fi

  dataset_path="$(pvesm path "$volid" 2>/dev/null || true)"
  if [ -n "$dataset_path" ]; then
    dataset="${dataset_path#/}"
    if zfs list -H "$dataset" >/dev/null 2>&1; then
      echo "$dataset"
      return 0
    fi
  fi

  return 1
}

add_target_skip() {
  local reason="$1"
  TARGET_SKIP_REASONS+=("$reason")
}

build_targets() {
  local matched_selector=0

  while IFS='|' read -r key raw_value; do
    local value=""
    local volid=""
    local rest_opts=""
    local storage=""
    local volname=""
    local storage_type=""
    local src_dataset=""
    local enc_prop=""
    local parent=""
    local base=""
    local dst_base=""
    local dst_dataset=""
    local dst_volid=""
    local pct_option=""
    local pct_value=""
    local snap_name=""

    value="$(trim_leading_space "$raw_value")"
    volid="${value%%,*}"
    rest_opts="${value#"$volid"}"

    if [ -n "$TARGET_VOLID" ] && [ "$volid" != "$TARGET_VOLID" ]; then
      continue
    fi
    matched_selector=1

    if [[ "$volid" != *:* ]]; then
      add_target_skip "${key}: skipped (non-storage mount: ${volid})"
      continue
    fi

    storage="${volid%%:*}"
    volname="${volid#*:}"

    case "$volname" in
      subvol-*) ;;
      *)
        add_target_skip "${key}: skipped (${volid} is not subvol-*)"
        continue
        ;;
    esac

    storage_type="$(get_storage_type "$storage")"
    [ -n "$storage_type" ] || die "unable to determine storage type for: $storage"
    if [ "$storage_type" != "zfspool" ]; then
      add_target_skip "${key}: skipped (${volid} storage type ${storage_type})"
      continue
    fi

    src_dataset="$(resolve_source_dataset "$storage" "$volname" "$volid" || true)"
    if [ -z "$src_dataset" ]; then
      add_target_skip "${key}: skipped (unable to resolve zfs dataset for ${volid})"
      continue
    fi

    if [ "$(zfs get -H -o value type "$src_dataset")" != "filesystem" ]; then
      add_target_skip "${key}: skipped (${src_dataset} is not filesystem)"
      continue
    fi

    enc_prop="$(zfs get -H -o value encryption "$src_dataset")"
    if [ "$enc_prop" != "off" ]; then
      add_target_skip "${key}: skipped (${src_dataset} already encrypted: ${enc_prop})"
      continue
    fi

    parent="${src_dataset%/*}"
    base="${src_dataset##*/}"
    dst_base="${base}-enc"
    dst_dataset="${parent}/${dst_base}"
    dst_volid="${storage}:${dst_base}"

    if zfs list -H "$dst_dataset" >/dev/null 2>&1; then
      add_target_skip "${key}: skipped (destination already exists: ${dst_dataset})"
      continue
    fi

    if [ "$key" = "rootfs" ]; then
      pct_option="--rootfs"
    else
      pct_option="--${key}"
    fi
    pct_value="${dst_volid}${rest_opts}"
    snap_name="${SNAP_PREFIX}-${key}"

    TARGET_KEYS+=("$key")
    TARGET_VOLIDS+=("$volid")
    TARGET_REST_OPTS+=("$rest_opts")
    TARGET_STORAGES+=("$storage")
    TARGET_VOLNAMES+=("$volname")
    TARGET_SRC_DATASETS+=("$src_dataset")
    TARGET_DST_DATASETS+=("$dst_dataset")
    TARGET_DST_VOLIDS+=("$dst_volid")
    TARGET_PCT_OPTIONS+=("$pct_option")
    TARGET_PCT_VALUES+=("$pct_value")
    TARGET_SNAPS+=("$snap_name")
  done < <(awk -F':' '/^[[:space:]]*(rootfs|mp[0-9]+)[[:space:]]*:/ {
    key=$1
    gsub(/[[:space:]]/, "", key)
    sub(/^[^:]*:[[:space:]]*/, "", $0)
    print key "|" $0
  }' "$CFG")

  if [ -n "$TARGET_VOLID" ] && [ "$matched_selector" -eq 0 ]; then
    die "requested VOLID not found in CT config: $TARGET_VOLID"
  fi
}

print_recap() {
  echo "== recap"
  echo "== CTID: $CTID"
  echo "== config: $CFG"
  echo "== target selector: ${TARGET_VOLID:-all eligible private datasets}"
  echo "== pass file: $PASS_FILE"
  echo "== convertible targets: ${#TARGET_KEYS[@]}"

  if [ "${#TARGET_KEYS[@]}" -gt 0 ]; then
    for i in "${!TARGET_KEYS[@]}"; do
      echo "  - ${TARGET_KEYS[$i]}: ${TARGET_VOLIDS[$i]}"
      echo "    source:      ${TARGET_SRC_DATASETS[$i]}"
      echo "    destination: ${TARGET_DST_DATASETS[$i]}"
      echo "    pct update:  ${TARGET_PCT_OPTIONS[$i]} ${TARGET_PCT_VALUES[$i]}"
    done
  fi

  if [ "${#TARGET_SKIP_REASONS[@]}" -gt 0 ]; then
    echo "== skipped during preflight"
    for reason in "${TARGET_SKIP_REASONS[@]}"; do
      echo "  - $reason"
    done
  fi
}

confirm_execution() {
  local answer=""

  if [ "$AUTO_YES" -eq 1 ]; then
    echo "== auto-confirm enabled (--yes)"
    return 0
  fi

  if [ ! -t 0 ]; then
    die "interactive confirmation required; re-run with --yes in non-interactive mode"
  fi

  echo
  read -r -p "Proceed with conversion? [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      die "operation aborted by user"
      ;;
  esac
}

convert_target() {
  local idx="$1"
  local src_dataset="${TARGET_SRC_DATASETS[$idx]}"
  local dst_dataset="${TARGET_DST_DATASETS[$idx]}"
  local dst_volid="${TARGET_DST_VOLIDS[$idx]}"
  local pct_option="${TARGET_PCT_OPTIONS[$idx]}"
  local pct_value="${TARGET_PCT_VALUES[$idx]}"
  local snap_name="${TARGET_SNAPS[$idx]}"
  local key="${TARGET_KEYS[$idx]}"
  local pass_size=""
  local pass_sha256=""
  local keystatus=""

  pass_size="$(stat -c '%s' "$PASS_FILE")"
  pass_sha256="$(sha256sum "$PASS_FILE" | awk '{print $1}')"

  echo "== [${key}] snapshot ${src_dataset}@${snap_name}"
  zfs snapshot "${src_dataset}@${snap_name}"

  # attempt to preserve the source mountpoint on the new dataset so Proxmox can mount it
  src_mp="$(zfs get -H -o value mountpoint "$src_dataset" 2>/dev/null || true)"
  if [ -n "${src_mp}" ] && [ "${src_mp}" != "-" ]; then
    recv_mount_opt="-o mountpoint=${src_mp}"
  else
    recv_mount_opt="-o mountpoint=legacy"
  fi

  echo "== [${key}] receiving encrypted dataset ${dst_dataset} (mountpoint: ${src_mp:-legacy})"
  zfs send -p "${src_dataset}@${snap_name}" | zfs recv -u \
    -o encryption=aes-256-gcm \
    -o keyformat=passphrase \
    -o keylocation="file://${PASS_FILE}" \
    -o compression=lz4 \
    "${recv_mount_opt}" \
    "${dst_dataset}"

  echo "== [${key}] storing metadata"
  zfs set "${PROP_NS}:lxc-ctid=${CTID}" "$dst_dataset"
  zfs set "${PROP_NS}:lxc-config-key=${key}" "$dst_dataset"
  zfs set "${PROP_NS}:lxc-source=${src_dataset}" "$dst_dataset"
  zfs set "${PROP_NS}:passfile=${PASS_FILE}" "$dst_dataset"
  zfs set "${PROP_NS}:passfile-size=${pass_size}" "$dst_dataset"
  zfs set "${PROP_NS}:passfile-sha256=${pass_sha256}" "$dst_dataset"
  zfs set "${PROP_NS}:note=default-unlock-via-passphrase-file" "$dst_dataset"
  keystatus="$(zfs get -H -o value keystatus "$dst_dataset")"
  if [ "$keystatus" != "available" ]; then
    echo "== [${key}] loading key"
    zfs load-key "$dst_dataset"
    keystatus="$(zfs get -H -o value keystatus "$dst_dataset")"
  fi
  [ "$keystatus" = "available" ] || die "new dataset key unavailable for ${dst_dataset}"

  echo "== [${key}] mounting ${dst_dataset}"
  zfs mount "$dst_dataset" || die "failed to mount ${dst_dataset}"

  echo "== [${key}] updating container config ${pct_option}"
  pct set "$CTID" "$pct_option" "$pct_value"

  TARGET_CONVERTED+=("${key}:${src_dataset}->${dst_dataset} (${dst_volid})")
}

print_summary() {
  echo
  echo "SUCCESS"
  echo "CTID:          $CTID"
  echo "Config backup: $CFG_BAK"
  echo
  echo "Converted targets (${#TARGET_CONVERTED[@]}):"
  for item in "${TARGET_CONVERTED[@]}"; do
    echo "  - $item"
  done

  if [ "${#TARGET_FINAL_SKIPPED[@]}" -gt 0 ]; then
    echo
    echo "Skipped targets (${#TARGET_FINAL_SKIPPED[@]}):"
    for item in "${TARGET_FINAL_SKIPPED[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "Snapshots created:"
  for i in "${!TARGET_CONVERTED[@]}"; do
    echo "  - ${TARGET_SRC_DATASETS[$i]}@${TARGET_SNAPS[$i]}"
  done

  echo
  echo "Verify with:"
  echo "  pct config $CTID | grep -E '^(rootfs|mp[0-9]+):'"
  echo "  pct start $CTID"
  echo "  pct exec $CTID -- df -h /"
  echo
  echo "When confirmed OK, remove old datasets manually:"
  for i in "${!TARGET_KEYS[@]}"; do
    echo "  zfs destroy ${TARGET_SRC_DATASETS[$i]}@${TARGET_SNAPS[$i]}"
    echo "  zfs destroy -r ${TARGET_SRC_DATASETS[$i]}"
  done
}

wait_for_ct_state() {
  local ctid="$1"
  local wanted="$2"
  local timeout="${3:-180}"
  local elapsed=0
  local state=""

  while [ "$elapsed" -lt "$timeout" ]; do
    state="$(pct status "$ctid" 2>/dev/null | awk '{print $2}')"
    if [ "$state" = "$wanted" ]; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

ensure_container_stopped() {
  local ctid="$1"
  local shutdown_timeout="${2:-180}"
  local wait_timeout="${3:-180}"
  local force_wait_timeout="${4:-60}"

  local state
  state="$(pct status "$ctid" 2>/dev/null | awk '{print $2}')"

  if [ "$state" = "stopped" ]; then
    echo "== container $ctid already stopped"
    return 0
  fi

  if [ "$state" != "running" ]; then
    die "container $ctid is in unexpected state: ${state:-unknown}"
  fi

  echo "== requesting graceful shutdown of container $ctid (timeout ${shutdown_timeout}s)"
  pct shutdown "$ctid" --timeout "$shutdown_timeout" || true

  echo "== waiting for container $ctid to reach stopped state"
  if wait_for_ct_state "$ctid" "stopped" "$wait_timeout"; then
    echo "== container $ctid stopped cleanly"
    return 0
  fi

  echo "== graceful shutdown timeout reached, forcing stop on container $ctid"
  pct stop "$ctid"

  echo "== waiting for forced stop completion"
  wait_for_ct_state "$ctid" "stopped" "$force_wait_timeout" || die "container $ctid did not reach stopped state"
  echo "== container $ctid is stopped"
}

for c in awk sed grep pct pvesm zfs stat sha256sum cp chmod date sleep; do
  need_cmd "$c"
done

[[ "$CTID" =~ ^[0-9]+$ ]] || die "CTID must be numeric"
[ -f "$CFG" ] || die "container config not found: $CFG"
[ -f "$PASS_FILE" ] || die "password file not found: $PASS_FILE"
[ -s "$PASS_FILE" ] || die "password file is empty: $PASS_FILE"

if [ -n "$TARGET_VOLID" ] && [[ "$TARGET_VOLID" != *:* ]]; then
  die "VOLID must be in STORAGE:VOLUME format"
fi

chmod 600 "$PASS_FILE"

build_targets
print_recap

if [ "${#TARGET_KEYS[@]}" -eq 0 ]; then
  if [ -n "$TARGET_VOLID" ]; then
    die "requested VOLID is not convertible: $TARGET_VOLID"
  fi
  die "no eligible private zfspool subvol datasets found for CT ${CTID}"
fi

confirm_execution

ensure_container_stopped "$CTID" "$SHUTDOWN_TIMEOUT" "$GRACEFUL_WAIT_TIMEOUT" "$FORCE_WAIT_TIMEOUT"

echo "== backup config to $CFG_BAK"
cp -a "$CFG" "$CFG_BAK"

for i in "${!TARGET_KEYS[@]}"; do
  convert_target "$i"
done

echo "== resulting config"
grep -E '^(rootfs|mp[0-9]+):' "$CFG" || true

TARGET_FINAL_SKIPPED=("${TARGET_SKIP_REASONS[@]}")

trap - EXIT
print_summary
