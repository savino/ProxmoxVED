#!/usr/bin/env bash
# shellcheck disable=SC2034
set -Eeuo pipefail

# encrypt-rpool-data-parent.sh
#
# Usage:
#   ./encrypt-rpool-data-parent.sh <PASS_FILE> [--yes]
#
# What it does:
# - validates that Proxmox storage `local-zfs` points to `rpool/data`
# - identifies CTs and VMs with disks backed by datasets or zvols under `rpool/data`
# - stops only the guests using storage under `rpool/data`
# - checks pool free space before starting the migration
# - creates a new encrypted parent dataset `rpool/data-enc`
# - recursively snapshots and migrates every direct child of `rpool/data`
# - switches `local-zfs` to the new encrypted parent by patching `/etc/pve/storage.cfg`
# - leaves the original `rpool/data` tree intact for manual rollback
#
# Notes:
# - only the passphrase file is required as input
# - use --yes for non-interactive execution
# - passphrase file must be available on an unencrypted filesystem

YW=$'\033[33m'
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

msg_info() {
  local msg="$1"
  printf ' %s %b...\n' "$HOLD" "${YW}${msg}"
}

msg_ok() {
  local msg="$1"
  printf '%b %b%s%b\n' "${BFR}" "${CM}" "${GN}${msg}" "${CL}"
}

msg_error() {
  local msg="$1"
  printf '%b %b%s%b\n' "${BFR}" "${CROSS}" "${RD}${msg}" "${CL}"
}

die() {
  msg_error "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

 AUTO_YES=0
 DRY_RUN=0
 RESTART_AFTER=0
 SWITCH_ONLY=0
 RESTORE=0
 PASS_FILE=""

 usage() {
  cat >&2 <<'EOF'
Usage:
  encrypt-rpool-data-parent.sh <PASS_FILE> [--yes] [--dry-run] [--restart] [--switch-only]
  encrypt-rpool-data-parent.sh --restore [--yes]

Options:
  --yes          Non-interactive: accept prompts
  --dry-run      Show recap and affected guests without making changes
  --restart      Start stopped guests after successful migration
  --switch-only  Skip ZFS migration, only patch storage.cfg and reload pvestatd (recovery mode)
  --restore      Restore previous storage.cfg and remount original datasets (use when switch failed)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --restart) RESTART_AFTER=1; shift ;;
    --switch-only) SWITCH_ONLY=1; shift ;;
    --restore) RESTORE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unexpected argument: $1" ;;
    *)
      if [ -z "$PASS_FILE" ]; then
        PASS_FILE="$1"
        shift
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
done

# PASS_FILE is required for normal operation; --restore does not need it
if [ "$RESTORE" -eq 0 ] && [ -z "$PASS_FILE" ]; then
  usage
  exit 1
fi

SOURCE_STORAGE="local-zfs"
SOURCE_PARENT="rpool/data"
DEST_PARENT="rpool/data-enc"
PROP_NS="custom.proxmox"
TS="$(date +%Y%m%d-%H%M%S)"
SNAP_NAME="pre-parent-encrypt-${TS}"
STORAGE_CFG="/etc/pve/storage.cfg"
STORAGE_CFG_BAK="/root/storage.cfg.bak.${TS}"
MOUNT_BAK="/root/orig-mounts.${TS}.txt"
POOL_ROOT="${SOURCE_PARENT%%/*}"
MIN_HEADROOM_BYTES=1073741824
SHUTDOWN_TIMEOUT=180
GRACEFUL_WAIT_TIMEOUT=180
FORCE_WAIT_TIMEOUT=60

declare -a SOURCE_CHILDREN=()
declare -a AFFECTED_CTS=()
declare -a AFFECTED_VMS=()
declare -a STOPPED_CTS=()
declare -a STOPPED_VMS=()
declare -a RECVD_DATASETS=()

CURRENT_STEP="(init)"
set_step() { CURRENT_STEP="$*"; }

cleanup_on_error() {
  local ec=$?
  if [ "$ec" -ne 0 ]; then
    printf '\n' >&2
    msg_error "aborted at step [${CURRENT_STEP}] with exit code ${ec}" >&2
    printf '\nDebug info:\n' >&2
    printf '  PASS_FILE:       %s\n' "${PASS_FILE:-<unset>}" >&2
    printf '  SOURCE_STORAGE:  %s\n' "${SOURCE_STORAGE:-<unset>}" >&2
    printf '  SOURCE_PARENT:   %s\n' "${SOURCE_PARENT:-<unset>}" >&2
    printf '  DEST_PARENT:     %s\n' "${DEST_PARENT:-<unset>}" >&2
    printf '  DRY_RUN:         %s\n' "${DRY_RUN:-0}" >&2
    printf '\nRollback hints:\n' >&2
    printf '  storage config backup: %s\n' "$STORAGE_CFG_BAK" >&2
    printf '  snapshot: %s@%s\n' "$SOURCE_PARENT" "$SNAP_NAME" >&2
    if [ "${#RECVD_DATASETS[@]}" -gt 0 ]; then
      printf '  received datasets:\n' >&2
      for dataset in "${RECVD_DATASETS[@]}"; do
        printf '    - %s\n' "$dataset" >&2
      done
    fi
    printf '  to roll back storage target:\n' >&2
    printf '    %s --restore --yes\n' "${0}" >&2
    printf '  manual fallback:\n' >&2
    printf '    cp %s %s\n' "$STORAGE_CFG_BAK" "$STORAGE_CFG" >&2
    printf '    systemctl reload-or-restart pvestatd\n' >&2
  fi
  exit "$ec"
}
trap cleanup_on_error EXIT

confirm_execution() {
  local answer=""
  if [ "$AUTO_YES" -eq 1 ]; then
    msg_ok "auto-confirm enabled (--yes)"
    return 0
  fi

  if [ ! -t 0 ]; then
    die "interactive confirmation required; re-run with --yes in non-interactive mode"
  fi

  printf '\nProceed with whole-parent encryption migration? [y/N]: '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) die "operation aborted by user" ;;
  esac
}

get_storage_type() {
  local storage="$1"
  pvesm status | awk -v s="$storage" '$1==s {print $2; exit}'
}

get_storage_pool() {
  local storage="$1"
  awk -v s="$storage" '
    /^[a-zA-Z]/ { in_sec = ($0 ~ "^[^ 	:]+:[ 	]*" s "[ 	]*$") }
    in_sec && $1 == "pool" { print $2; exit }
  ' "$STORAGE_CFG"
}

resolve_volid_dataset() {
  local storage="$1"
  local volname="$2"
  local volid="$3"
  local pool=""
  local candidate=""
  local path=""

  pool="$(get_storage_pool "$storage")"
  if [ -n "$pool" ]; then
    candidate="${pool}/${volname}"
    if zfs list -H "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  path="$(pvesm path "$volid" 2>/dev/null || true)"
  case "$path" in
    /dev/zvol/*)
      candidate="${path#/dev/zvol/}"
      ;;
    /*)
      candidate="${path#/}"
      ;;
    *)
      candidate=""
      ;;
  esac

  if [ -n "$candidate" ] && zfs list -H "$candidate" >/dev/null 2>&1; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

append_unique() {
  local value="$1"
  shift
  local item=""
  for item in "$@"; do
    [ "$item" = "$value" ] && return 0
  done
  return 1
}

collect_source_children() {
  local child=""
  set_step "collect child datasets"
  msg_info "listing child datasets under ${SOURCE_PARENT}"
  while IFS= read -r child; do
    [ -n "$child" ] || continue
    SOURCE_CHILDREN+=("$child")
  done < <(zfs list -H -r -d 1 -o name "$SOURCE_PARENT" | awk -v parent="$SOURCE_PARENT" '$1 != parent')

  if [ "${#SOURCE_CHILDREN[@]}" -eq 0 ]; then
    die "no child datasets found under ${SOURCE_PARENT} — is the storage pool correct?"
  fi
  msg_ok "found ${#SOURCE_CHILDREN[@]} child dataset(s) under ${SOURCE_PARENT}"
}

collect_affected_cts() {
  set_step "collect affected CTs"
  msg_info "scanning CT configs for disks under ${SOURCE_PARENT}"
  local conf=""
  local ctid=""
  local key=""
  local raw_value=""
  local value=""
  local volid=""
  local storage=""
  local volname=""
  local dataset=""

  for conf in /etc/pve/lxc/*.conf; do
    [ -f "$conf" ] || continue
    ctid="${conf##*/}"
    ctid="${ctid%.conf}"
    while IFS='|' read -r key raw_value; do
      value="${raw_value#"${raw_value%%[![:space:]]*}"}"
      volid="${value%%,*}"
      [[ "$volid" == *:* ]] || continue
      storage="${volid%%:*}"
      volname="${volid#*:}"
      dataset="$(resolve_volid_dataset "$storage" "$volname" "$volid" || true)"
      [[ "$dataset" == "${SOURCE_PARENT}"/* ]] || continue
      if ! append_unique "$ctid" "${AFFECTED_CTS[@]}"; then
        AFFECTED_CTS+=("$ctid")
      fi
      break
    done < <(awk -F':' '/^[[:space:]]*(rootfs|mp[0-9]+)[[:space:]]*:/ {
      key=$1
      gsub(/[[:space:]]/, "", key)
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      print key "|" $0
    }' "$conf")
  done
  msg_ok "found ${#AFFECTED_CTS[@]} affected CT(s)"
}

collect_affected_vms() {
  set_step "collect affected VMs"
  msg_info "scanning VM configs for disks under ${SOURCE_PARENT}"
  local conf=""
  local vmid=""
  local key=""
  local raw_value=""
  local value=""
  local volid=""
  local storage=""
  local volname=""
  local dataset=""

  for conf in /etc/pve/qemu-server/*.conf; do
    [ -f "$conf" ] || continue
    vmid="${conf##*/}"
    vmid="${vmid%.conf}"
    while IFS='|' read -r key raw_value; do
      value="${raw_value#"${raw_value%%[![:space:]]*}"}"
      volid="${value%%,*}"
      [[ "$volid" == *:* ]] || continue
      storage="${volid%%:*}"
      volname="${volid#*:}"
      dataset="$(resolve_volid_dataset "$storage" "$volname" "$volid" || true)"
      [[ "$dataset" == "${SOURCE_PARENT}"/* ]] || continue
      if ! append_unique "$vmid" "${AFFECTED_VMS[@]}"; then
        AFFECTED_VMS+=("$vmid")
      fi
      break
    done < <(awk -F':' '/^[[:space:]]*((virtio|scsi|sata|ide)[0-9]+|efidisk0|tpmstate0)[[:space:]]*:/ {
      key=$1
      gsub(/[[:space:]]/, "", key)
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      print key "|" $0
    }' "$conf")
  done
  msg_ok "found ${#AFFECTED_VMS[@]} affected VM(s)"
}

wait_for_ct_state() {
  local ctid="$1"
  local wanted="$2"
  local timeout="$3"
  local elapsed=0
  local state=""

  while [ "$elapsed" -lt "$timeout" ]; do
    state="$(pct status "$ctid" 2>/dev/null | awk '{print $2}')"
    [ "$state" = "$wanted" ] && return 0
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

wait_for_vm_state() {
  local vmid="$1"
  local wanted="$2"
  local timeout="$3"
  local elapsed=0
  local state=""

  while [ "$elapsed" -lt "$timeout" ]; do
    state="$(qm status "$vmid" 2>/dev/null | awk '{print $2}')"
    [ "$state" = "$wanted" ] && return 0
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

stop_ct_if_needed() {
  local ctid="$1"
  local state=""
  state="$(pct status "$ctid" 2>/dev/null | awk '{print $2}')"

  if [ "$state" = "stopped" ]; then
    return 0
  fi
  [ "$state" = "running" ] || die "CT ${ctid} is in unexpected state: ${state:-unknown}"

  msg_info "requesting graceful shutdown of CT ${ctid}"
  pct shutdown "$ctid" --timeout "$SHUTDOWN_TIMEOUT" || true
  if wait_for_ct_state "$ctid" stopped "$GRACEFUL_WAIT_TIMEOUT"; then
    msg_ok "CT ${ctid} stopped cleanly"
  else
    msg_info "forcing stop of CT ${ctid}"
    pct stop "$ctid"
    wait_for_ct_state "$ctid" stopped "$FORCE_WAIT_TIMEOUT" || die "CT ${ctid} did not stop"
    msg_ok "CT ${ctid} forcibly stopped"
  fi
  STOPPED_CTS+=("$ctid")
}

stop_vm_if_needed() {
  local vmid="$1"
  local state=""
  state="$(qm status "$vmid" 2>/dev/null | awk '{print $2}')"

  if [ "$state" = "stopped" ]; then
    return 0
  fi
  [ "$state" = "running" ] || die "VM ${vmid} is in unexpected state: ${state:-unknown}"

  msg_info "requesting graceful shutdown of VM ${vmid}"
  qm shutdown "$vmid" --timeout "$SHUTDOWN_TIMEOUT" || true
  if wait_for_vm_state "$vmid" stopped "$GRACEFUL_WAIT_TIMEOUT"; then
    msg_ok "VM ${vmid} stopped cleanly"
  else
    msg_info "forcing stop of VM ${vmid}"
    qm stop "$vmid"
    wait_for_vm_state "$vmid" stopped "$FORCE_WAIT_TIMEOUT" || die "VM ${vmid} did not stop"
    msg_ok "VM ${vmid} forcibly stopped"
  fi
  STOPPED_VMS+=("$vmid")
}

start_ct_if_needed() {
  local ctid="$1"
  msg_info "starting CT ${ctid}"
  pct start "$ctid" || die "failed to start CT ${ctid}"
  if wait_for_ct_state "$ctid" running 120; then
    msg_ok "CT ${ctid} started"
  else
    die "CT ${ctid} failed to reach running state"
  fi
}

start_vm_if_needed() {
  local vmid="$1"
  msg_info "starting VM ${vmid}"
  qm start "$vmid" || die "failed to start VM ${vmid}"
  if wait_for_vm_state "$vmid" running 120; then
    msg_ok "VM ${vmid} started"
  else
    die "VM ${vmid} failed to reach running state"
  fi
}

check_space() {
  local used_bytes=""
  local available_bytes=""
  msg_info "reading space usage for ${SOURCE_PARENT}"
  used_bytes="$(zfs get -Hp -o value used "$SOURCE_PARENT")"
  available_bytes="$(zfs get -Hp -o value available "$POOL_ROOT")"
  [ "$used_bytes" -gt 0 ] || die "unable to determine used space for ${SOURCE_PARENT}"
  [ "$available_bytes" -gt 0 ] || die "unable to determine available space for ${POOL_ROOT}"
  msg_info "used=${used_bytes} bytes  available=${available_bytes} bytes  required=$(( used_bytes + MIN_HEADROOM_BYTES )) bytes"
  if [ "$available_bytes" -lt $(( used_bytes + MIN_HEADROOM_BYTES )) ]; then
    die "insufficient free space in ${POOL_ROOT}: need $((used_bytes + MIN_HEADROOM_BYTES)) bytes, have ${available_bytes}"
  fi
  msg_ok "space check passed"
}

print_recap() {
  local child=""
  printf '== recap\n'
  printf '== source storage: %s\n' "$SOURCE_STORAGE"
  printf '== source parent:  %s\n' "$SOURCE_PARENT"
  printf '== dest parent:    %s\n' "$DEST_PARENT"
  printf '== pass file:      %s\n' "$PASS_FILE"
  printf '== snapshot name:  %s\n' "$SNAP_NAME"
  printf '== CTs affected:   %s\n' "${#AFFECTED_CTS[@]}"
  printf '== VMs affected:   %s\n' "${#AFFECTED_VMS[@]}"
  printf '== child datasets: %s\n' "${#SOURCE_CHILDREN[@]}"

  if [ "${#AFFECTED_CTS[@]}" -gt 0 ]; then
    printf 'CT list:\n'
    for child in "${AFFECTED_CTS[@]}"; do
      printf '  - %s\n' "$child"
    done
  fi

  if [ "${#AFFECTED_VMS[@]}" -gt 0 ]; then
    printf 'VM list:\n'
    for child in "${AFFECTED_VMS[@]}"; do
      printf '  - %s\n' "$child"
    done
  fi

  printf 'Datasets/zvols to migrate:\n'
  for child in "${SOURCE_CHILDREN[@]}"; do
    printf '  - %s -> %s/%s\n' "$child" "$DEST_PARENT" "${child##*/}"
  done
}

validate_environment() {
  local storage_type=""
  local storage_pool=""
  local enc_val=""

  set_step "check required commands"
  msg_info "checking required commands"
  need_cmd awk
  need_cmd cp
  need_cmd date
  need_cmd pct
  need_cmd pvesm
  need_cmd qm
  need_cmd sha256sum
  need_cmd sleep
  need_cmd stat
  need_cmd zfs
  msg_ok "all required commands found"

  set_step "check pv"
  if command -v pv >/dev/null 2>&1; then
    msg_ok "pv available — transfer progress will be displayed"
  else
    msg_info "pv not found — transfer will run without live progress (install with: apt install pv)"
  fi

  set_step "validate passphrase file"
  msg_info "validating passphrase file: ${PASS_FILE}"
  [ -f "$PASS_FILE" ] || die "passphrase file not found: $PASS_FILE"
  [ -s "$PASS_FILE" ] || die "passphrase file is empty: $PASS_FILE"
  chmod 600 "$PASS_FILE"
  msg_ok "passphrase file OK"

  set_step "validate storage config"
  msg_info "checking storage config: ${STORAGE_CFG}"
  [ -f "$STORAGE_CFG" ] || die "missing storage config: $STORAGE_CFG"
  msg_ok "storage config exists"

  set_step "validate source dataset"
  msg_info "checking source dataset: ${SOURCE_PARENT}"
  zfs list -H "$SOURCE_PARENT" >/dev/null 2>&1 || die "source dataset not found: $SOURCE_PARENT"
  msg_ok "source dataset exists: ${SOURCE_PARENT}"

  set_step "validate dest dataset absent"
  msg_info "checking destination does not already exist: ${DEST_PARENT}"
  if zfs list -H "$DEST_PARENT" >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      die "destination dataset already exists: $DEST_PARENT (dry-run caught existing migration target; destroy it or use --restore before running migration)"
    fi
    die "destination dataset already exists: $DEST_PARENT"
  fi
  msg_ok "destination dataset absent: ${DEST_PARENT}"

  set_step "validate storage type"
  msg_info "checking storage type for ${SOURCE_STORAGE}"
  storage_type="$(get_storage_type "$SOURCE_STORAGE")"
  if [ -z "$storage_type" ]; then
    die "storage '${SOURCE_STORAGE}' not found in pvesm status"
  fi
  [ "$storage_type" = "zfspool" ] || die "${SOURCE_STORAGE} is type '${storage_type}', expected 'zfspool'"
  msg_ok "storage type OK: ${storage_type}"

  set_step "validate storage pool"
  msg_info "checking pool for ${SOURCE_STORAGE}"
  storage_pool="$(get_storage_pool "$SOURCE_STORAGE")"
  msg_info "pool value read from storage.cfg: '${storage_pool}'"
  if [ -z "$storage_pool" ]; then
    die "could not determine pool for storage '${SOURCE_STORAGE}' in ${STORAGE_CFG} — check that 'pool' is set under '${SOURCE_STORAGE}'"
  fi
  [ "$storage_pool" = "$SOURCE_PARENT" ] || die "${SOURCE_STORAGE} pool is '${storage_pool}', expected '${SOURCE_PARENT}'"
  msg_ok "storage pool OK: ${storage_pool}"

  set_step "validate source encryption status"
  msg_info "checking encryption on ${SOURCE_PARENT}"
  enc_val="$(zfs get -H -o value encryption "$SOURCE_PARENT")"
  msg_info "encryption property = ${enc_val}"
  [ "$enc_val" = "off" ] || die "${SOURCE_PARENT} is already encrypted (encryption=${enc_val})"
  msg_ok "source dataset is unencrypted — can proceed"

  set_step "check available space"
  check_space
}

migrate_children() {
  local source_child=""
  local dest_child=""
  local pass_size=""
  local pass_sha256=""

  pass_size="$(stat -c '%s' "$PASS_FILE")"
  pass_sha256="$(sha256sum "$PASS_FILE" | awk '{print $1}')"

  msg_info "creating encrypted parent ${DEST_PARENT}"
  zfs create \
    -o encryption=aes-256-gcm \
    -o keyformat=passphrase \
    -o keylocation="file://${PASS_FILE}" \
    -o mountpoint=none \
    "$DEST_PARENT"
  msg_ok "created encrypted parent ${DEST_PARENT}"

  msg_info "storing parent metadata"
  zfs set "${PROP_NS}:source-parent=${SOURCE_PARENT}" "$DEST_PARENT"
  zfs set "${PROP_NS}:passfile=${PASS_FILE}" "$DEST_PARENT"
  zfs set "${PROP_NS}:passfile-size=${pass_size}" "$DEST_PARENT"
  zfs set "${PROP_NS}:passfile-sha256=${pass_sha256}" "$DEST_PARENT"
  zfs set "${PROP_NS}:note=whole-parent-migration" "$DEST_PARENT"
  msg_ok "stored parent metadata"

  # capture original mountpoints for children so we can restore them on the new datasets
  msg_info "recording original mountpoints for child datasets"
  declare -A ORIG_MOUNT=()
  for source_child in "${SOURCE_CHILDREN[@]}"; do
    ORIG_MOUNT["$source_child"]="$(zfs get -H -o value mountpoint "$source_child" 2>/dev/null || true)"
  done
  msg_ok "recorded mountpoints for ${#SOURCE_CHILDREN[@]} datasets"

  # Ensure key is loaded and parent is mountable before child migration.
  local parent_keystatus
  parent_keystatus="$(zfs get -H -o value keystatus "$DEST_PARENT" 2>/dev/null || echo "")"
  if [ "$parent_keystatus" != "available" ]; then
    msg_info "loading key for ${DEST_PARENT}"
    zfs load-key "$DEST_PARENT" || die "failed to load key for ${DEST_PARENT}"
  fi
  parent_keystatus="$(zfs get -H -o value keystatus "$DEST_PARENT" 2>/dev/null || echo "")"
  [ "$parent_keystatus" = "available" ] || die "key for ${DEST_PARENT} is not available (keystatus=${parent_keystatus:-unknown})"
  msg_ok "key available for ${DEST_PARENT}"

  # Set up mountpoints: source stays disabled, destination mounts under /rpool/data-enc
  msg_info "unmounting ${SOURCE_PARENT} and setting mountpoints"
  if zfs get -H -o value mounted "$SOURCE_PARENT" 2>/dev/null | grep -q '^yes$'; then
    zfs unmount "$SOURCE_PARENT" || msg_error "failed to unmount ${SOURCE_PARENT}"
  fi
  zfs set mountpoint=none "$SOURCE_PARENT" || die "failed to set mountpoint=none for ${SOURCE_PARENT}"
  zfs set mountpoint="/${DEST_PARENT}" "$DEST_PARENT" || die "failed to set mountpoint=/${DEST_PARENT} for ${DEST_PARENT}"
  if ! zfs get -H -o value mounted "$DEST_PARENT" 2>/dev/null | grep -q '^yes$'; then
    zfs mount "$DEST_PARENT" || die "failed to mount parent dataset ${DEST_PARENT}"
  fi
  msg_ok "parent dataset mounted: ${DEST_PARENT} at /${DEST_PARENT}"

  msg_info "creating recursive snapshot ${SOURCE_PARENT}@${SNAP_NAME}"
  zfs snapshot -r "${SOURCE_PARENT}@${SNAP_NAME}"
  msg_ok "snapshot created"

  for source_child in "${SOURCE_CHILDREN[@]}"; do
    dest_child="${DEST_PARENT}/${source_child##*/}"
    local child_used=""
    child_used="$(zfs get -Hp -o value used "$source_child" 2>/dev/null || echo 0)"
    printf '\n'
    msg_info "migrating ${source_child} → ${dest_child}  (estimated size: $(numfmt --to=iec-i --suffix=B "$child_used" 2>/dev/null || printf '%s bytes' "$child_used"))"
    if command -v pv >/dev/null 2>&1; then
      zfs send -R "${source_child}@${SNAP_NAME}" \
        | pv -s "$child_used" \
             -F '%t elapsed  %b transferred  %r  ETA %e  [%B]' \
             --interval 1 \
        | zfs recv -u -F "$dest_child"
    else
      zfs send -R "${source_child}@${SNAP_NAME}" | zfs recv -u -F "$dest_child"
    fi
    # restore original mountpoint if present; first free the path on the source
    local orig_mp="${ORIG_MOUNT["$source_child"]}"
    local source_type
    source_type="$(zfs get -H -o value type "$source_child" 2>/dev/null || echo "")"
    local dest_type
    dest_type="$(zfs get -H -o value type "$dest_child" 2>/dev/null || echo "")"

    if [ -n "${orig_mp}" ] && [ "${orig_mp}" != "none" ] && [ "${source_type}" = "filesystem" ]; then
      msg_info "unmounting original ${source_child} (mounted=$(zfs get -H -o value mounted "$source_child" 2>/dev/null || echo unknown))"
      local mounted_val
      mounted_val="$(zfs get -H -o value mounted "$source_child" 2>/dev/null || echo "no")"
      if [ "${mounted_val}" = "yes" ]; then
        zfs unmount "$source_child" >/dev/null 2>&1 || msg_error "failed to unmount ${source_child}"
      fi
      # clear the original mountpoint so the path is free; keep orig_mp in memory/property
      zfs set mountpoint=none "$source_child" >/dev/null 2>&1 || msg_error "failed to clear mountpoint for ${source_child}"
      msg_ok "unmounted and cleared mountpoint for ${source_child}"
    fi

    if [ -n "${orig_mp}" ] && [ "${orig_mp}" != "none" ] && [ "${dest_type}" = "filesystem" ]; then
      msg_info "recording original mountpoint on ${dest_child} and applying it"
      # persist original mountpoint as a custom property for later recovery
      zfs set "${PROP_NS}:orig-mount=${orig_mp}" "$dest_child" >/dev/null 2>&1 || msg_error "failed to record original mountpoint on ${dest_child}"
      zfs set mountpoint="/${DEST_PARENT}/${source_child##*/}" "$dest_child" || msg_error "failed to set mountpoint for ${dest_child}"
      # attempt to mount (requires key to be loaded)
      if zfs mount "$dest_child"; then
        msg_ok "mounted ${dest_child}"
      else
        msg_info "could not mount ${dest_child} now; will require manual mount or key load"
      fi
    else
      msg_info "no original mountpoint for ${source_child} or dest not a filesystem; leaving ${dest_child} with inherited mountpoint"
    fi

    RECVD_DATASETS+=("$dest_child")
    msg_ok "migrated ${source_child}"
  done
}

switch_storage() {
  msg_info "backing up ${STORAGE_CFG} to ${STORAGE_CFG_BAK}"
  cp -a "$STORAGE_CFG" "$STORAGE_CFG_BAK"
  msg_ok "storage config backed up"

  # pvesm set cannot change 'pool' (it is a fixed parameter in Proxmox).
  # Edit storage.cfg directly: replace the pool line inside the storage block.
  msg_info "patching ${STORAGE_CFG}: setting pool to ${DEST_PARENT} for ${SOURCE_STORAGE}"
  local in_block=0
  local patched=0
  local tmp=""
  # create tmp file in same directory as storage.cfg so mv is atomic and we avoid permission issues
  tmp="$(mktemp "${STORAGE_CFG}.tmp.XXXX")"
  while IFS= read -r line; do
    if printf '%s\n' "$line" | grep -qE "^zfspool:[[:space:]]*${SOURCE_STORAGE}[[:space:]]*$"; then
      in_block=1
    elif printf '%s\n' "$line" | grep -qE "^[a-zA-Z]"; then
      in_block=0
    fi
    if [ "$in_block" -eq 1 ] && printf '%s\n' "$line" | grep -qE "^[[:space:]]+pool[[:space:]]"; then
      printf '\tpool %s\n' "$DEST_PARENT" >>"$tmp"
      patched=1
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$STORAGE_CFG"

  if [ "$patched" -eq 0 ]; then
    rm -f "$tmp"
    die "could not find 'pool' line for storage '${SOURCE_STORAGE}' in ${STORAGE_CFG}"
  fi

  mv -f "$tmp" "$STORAGE_CFG"
  msg_ok "storage.cfg patched: ${SOURCE_STORAGE} pool → ${DEST_PARENT}"

  msg_info "reloading pvestatd to pick up new storage config"
  systemctl reload-or-restart pvestatd 2>/dev/null || true
  msg_ok "pvestatd reloaded"

  # Verify the change was applied
  local actual_pool=""
  actual_pool="$(get_storage_pool "$SOURCE_STORAGE")"
  [ "$actual_pool" = "$DEST_PARENT" ] || \
    die "storage pool was not updated correctly: expected '${DEST_PARENT}', found '${actual_pool}'"
  msg_ok "storage ${SOURCE_STORAGE} now points to ${DEST_PARENT}"
}

# Prepare for switch-only: record original mountpoints and unmount originals
prepare_switch_unmount_sources() {
  msg_info "recording and unmounting original source datasets"
  : >"$MOUNT_BAK" || die "cannot write mount backup: $MOUNT_BAK"
  local src=""
  for src in "${SOURCE_CHILDREN[@]}"; do
    local mp
    mp="$(zfs get -H -o value mountpoint "$src" 2>/dev/null || echo "")"
    printf '%s %s\n' "$src" "${mp:-none}" >>"$MOUNT_BAK"
    if [ -n "${mp}" ] && [ "${mp}" != "none" ]; then
      local mounted
      mounted="$(zfs get -H -o value mounted "$src" 2>/dev/null || echo "no")"
      if [ "$mounted" = "yes" ]; then
        msg_info "unmounting ${src}"
        zfs unmount "$src" || die "failed to unmount ${src}"
      fi
      msg_info "clearing mountpoint for ${src}"
      zfs set mountpoint=none "$src" || die "failed to clear mountpoint for ${src}"
      msg_ok "unmounted and cleared mountpoint for ${src}"
    else
      msg_info "no mountpoint set for ${src}; skipping"
    fi
  done
  msg_ok "original mountpoints recorded to ${MOUNT_BAK}"
}

# Restore previous state: restore storage.cfg, unmount dest children and remount originals
restore_state() {
  msg_info "locating storage.cfg backup to restore"
  local stor_bak
  stor_bak=""
  local f
  for f in /root/storage.cfg.bak.*; do
    [ -e "$f" ] || continue
    if [ -z "$stor_bak" ] || [ "$f" -nt "$stor_bak" ]; then
      stor_bak="$f"
    fi
  done
  [ -n "$stor_bak" ] || die "no storage.cfg backup found in /root"
  msg_info "restoring storage.cfg from ${stor_bak}"
  # write backup into a temp file inside /etc/pve and atomically move it
  local tmp
  tmp="$(mktemp "${STORAGE_CFG}.tmp.XXXX")" || die "failed to create temp file in $(dirname "$STORAGE_CFG")"
  if ! cat "$stor_bak" >"$tmp"; then
    rm -f "$tmp" || true
    die "failed to write temp storage config"
  fi
  if ! mv -f "$tmp" "$STORAGE_CFG"; then
    rm -f "$tmp" || true
    die "failed to move restored config into place"
  fi
  msg_ok "restored ${STORAGE_CFG}"

  msg_info "reloading pvestatd"
  systemctl reload-or-restart pvestatd 2>/dev/null || true
  msg_ok "pvestatd reloaded"

  msg_info "unmounting new encrypted datasets under ${DEST_PARENT} (if any)"
    if zfs list -H "$DEST_PARENT" >/dev/null 2>&1; then
      while IFS= read -r d; do
        if zfs get -H -o value mounted "$d" 2>/dev/null | grep -q '^yes$'; then
          zfs unmount "$d" >/dev/null 2>&1 || true
        fi
        zfs set mountpoint=none "$d" >/dev/null 2>&1 || true
      done < <(zfs list -H -r -d 1 -o name "$DEST_PARENT")
    fi
    msg_ok "unmounted new datasets"

    msg_info "restoring original mountpoints from backup"
    local mb
    mb=""
    for f in /root/orig-mounts.*; do
      [ -e "$f" ] || continue
      if [ -z "$mb" ] || [ "$f" -nt "$mb" ]; then
        mb="$f"
      fi
    done

    if [ -n "$mb" ]; then
      msg_info "using mount backup ${mb}"
      local line dataset orig
      while IFS= read -r line || [ -n "$line" ]; do
        dataset="${line%% *}"
        orig="${line#* }"
        if [ -n "$orig" ] && [ "$orig" != "none" ]; then
          zfs set mountpoint="$orig" "$dataset" >/dev/null 2>&1 || true
          if zfs get -H -o value mounted "$dataset" 2>/dev/null | grep -q '^yes$'; then
            msg_ok "$dataset already mounted at $orig"
          else
            if zfs mount "$dataset" 2>/dev/null; then
              msg_ok "mounted $dataset at $orig"
            else
              msg_error "failed to mount $dataset at $orig"
            fi
          fi
        fi
      done < "$mb"
      msg_ok "original mountpoints restored (where possible)"
    else
      msg_info "no mount backup found; attempting to recover from ${PROP_NS}:orig-mount properties on ${DEST_PARENT} children"
      if zfs list -H "$DEST_PARENT" >/dev/null 2>&1; then
        while IFS= read -r d; do
          orig_mp="$(zfs get -H -o value ${PROP_NS}:orig-mount "$d" 2>/dev/null || true)"
          original="${SOURCE_PARENT}/${d##*/}"
          if [ -n "$orig_mp" ] && [ "$orig_mp" != "-" ] && [ "$orig_mp" != "none" ]; then
            if ! zfs list -H "$original" >/dev/null 2>&1; then
              msg_error "original dataset missing: $original"
              continue
            fi
            zfs set mountpoint="$orig_mp" "$original" >/dev/null 2>&1 || true
            if zfs get -H -o value mounted "$original" 2>/dev/null | grep -q '^yes$'; then
              msg_ok "$original already mounted at $orig_mp"
            else
              if zfs mount "$original" 2>/dev/null; then
                msg_ok "mounted $original at $orig_mp"
              else
                msg_error "failed to mount $original at $orig_mp"
              fi
            fi
          fi
        done < <(zfs list -H -r -d 1 -o name "$DEST_PARENT")
        msg_ok "restored original mountpoints from properties (where possible)"
      else
        die "no mount backup found and ${DEST_PARENT} not present to recover properties"
      fi
    fi
}

print_summary() {
  local dataset=""
  printf '\nSUCCESS\n'
  printf 'Storage backup: %s\n' "$STORAGE_CFG_BAK"
  printf 'Snapshot:       %s@%s\n' "$SOURCE_PARENT" "$SNAP_NAME"
  printf 'New parent:     %s\n' "$DEST_PARENT"
  printf '\nMigrated children:\n'
  for dataset in "${RECVD_DATASETS[@]}"; do
    printf '  - %s\n' "$dataset"
  done
  printf '\nPost-checks:\n'
  printf '  pvesm status\n'
  printf '  awk '\''/^zfspool:[[:space:]]*%s$/,/^[a-zA-Z]/{print}'\'' /etc/pve/storage.cfg\n' "$SOURCE_STORAGE"
  printf '  zfs get encryption,keystatus,mountpoint,mounted %s\n' "$DEST_PARENT"
  printf '  pct list\n'
  printf '  qm list\n'
  printf '\nRollback target:\n'
  printf '  %s --restore --yes\n' "${0}"
}


if [ "$RESTORE" -eq 1 ]; then
  set_step "restore state"
  restore_state
  trap - EXIT
  print_summary
  exit 0
fi

set_step "validate environment"
validate_environment

if [ "$SWITCH_ONLY" -eq 1 ]; then
  msg_info "--switch-only: skipping ZFS migration, patching storage.cfg only"
  confirm_execution
  set_step "collect child datasets"
  collect_source_children
  set_step "prepare for switch: unmount originals"
  prepare_switch_unmount_sources
  set_step "switch storage"
  switch_storage
  trap - EXIT
  print_summary
  exit 0
fi

set_step "collect child datasets"
collect_source_children

set_step "collect affected CTs"
collect_affected_cts

set_step "collect affected VMs"
collect_affected_vms

print_recap

if [ "$DRY_RUN" -eq 1 ]; then
  trap - EXIT
  printf '\n'
  msg_ok "DRY-RUN complete — no changes were made"
  exit 0
fi

confirm_execution

set_step "stop affected VMs"
for vmid in "${AFFECTED_VMS[@]}"; do
  stop_vm_if_needed "$vmid"
done

set_step "stop affected CTs"
for ctid in "${AFFECTED_CTS[@]}"; do
  stop_ct_if_needed "$ctid"
done

# Unmount all rpool/data children before unmounting parent
set_step "unmount rpool/data children"
msg_info "unmounting all children of ${SOURCE_PARENT}"
for child in "${SOURCE_CHILDREN[@]}"; do
  if zfs get -H -o value mounted "$child" 2>/dev/null | grep -q '^yes$'; then
    zfs unmount "$child" || msg_error "failed to unmount $child"
  fi
done
msg_ok "all children of ${SOURCE_PARENT} unmounted"

# Now safe to unmount rpool/data and change its mountpoint
set_step "unmount rpool/data and set mountpoint=none"
if zfs get -H -o value mounted "$SOURCE_PARENT" 2>/dev/null | grep -q '^yes$'; then
  zfs unmount "$SOURCE_PARENT" || msg_error "failed to unmount ${SOURCE_PARENT}"
fi
zfs set mountpoint=none "$SOURCE_PARENT" || die "failed to set mountpoint=none for ${SOURCE_PARENT}"
msg_ok "${SOURCE_PARENT} unmounted and mountpoint set to none"

set_step "migrate children"
migrate_children

set_step "switch storage"
switch_storage

trap - EXIT
print_summary
if [ "$RESTART_AFTER" -eq 1 ]; then
  set_step "restart guests"
  msg_info "restarting previously stopped guests"
  for vmid in "${STOPPED_VMS[@]}"; do
    start_vm_if_needed "$vmid"
  done
  for ctid in "${STOPPED_CTS[@]}"; do
    start_ct_if_needed "$ctid"
  done
  msg_ok "restarted guests"
fi
