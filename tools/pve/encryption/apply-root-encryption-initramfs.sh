#!/bin/sh
# Run in a minimal initramfs (BusyBox ash) - keep options portable
set -eu

# apply-root-encryption-initramfs.sh
#
# Offline helper meant to be run from initramfs/rescue shell to encrypt
# rpool/ROOT while rootfs is not mounted.
#
# Usage:
#   ./apply-root-encryption-initramfs.sh <PASS_FILE> [--snapshot <name>] [--yes] [--keep-copy]
#   ./apply-root-encryption-initramfs.sh [<PASS_FILE>] [--snapshot <name>] --recover-root [--yes]

PASS_FILE=""
AUTO_YES=0
KEEP_COPY=0
SNAPSHOT_NAME=""
RECOVERY_MODE=0

POOL="rpool"
SOURCE_ROOT="rpool/ROOT"
TEMP_ROOT="rpool/root-unencrypted-copy"
ROOT_CHILD_EXPECTED="pve-1"
TS="$(date +%Y%m%d-%H%M%S)"
COPY_SNAP="reenc-${TS}"

# ---------------------------------------------------------------------------
# Verbose logging helpers
# _con: write to /dev/console DIRECTLY so messages are ALWAYS visible on
# screen even when stdout/stderr is redirected to a log file by the hook.
# ---------------------------------------------------------------------------
_ts() { date '+%H:%M:%S' 2>/dev/null || printf '??:??:??'; }

_con() {
  printf '[%s] %s\n' "$(_ts)" "$*"
  printf '[%s] %s\n' "$(_ts)" "$*" >/dev/console 2>/dev/null || true
}

_step() {
  local n="$1" total="$2" desc="$3"
  printf '\n============================================================\n'
  printf '  STEP %s/%s: %s\n' "$n" "$total" "$desc"
  printf '============================================================\n'
  printf '\n[%s] STEP %s/%s: %s\n' "$(_ts)" "$n" "$total" "$desc" >/dev/console 2>/dev/null || true
}

_ok() {
  printf '[OK]  %s\n' "$*"
  printf '[OK]  %s\n' "$*" >/dev/console 2>/dev/null || true
}

_err() {
  printf '[ERR] %s\n' "$*" >&2
  printf '[ERR] %s\n' "$*" >/dev/console 2>/dev/null || true
}

_ds_size() {
  zfs get -H -o value used "$1" 2>/dev/null || printf 'unknown'
}

die() {
  _err "FATAL: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

usage() {
  cat <<'EOF' >&2
Usage:
  apply-root-encryption-initramfs.sh <PASS_FILE> [--snapshot <name>] [--yes] [--keep-copy]
  apply-root-encryption-initramfs.sh [<PASS_FILE>] [--snapshot <name>] --recover-root [--yes]

Options:
  --snapshot NAME      source snapshot name on rpool/ROOT (without dataset prefix)
  --yes                non-interactive confirmation
  --keep-copy          keep temp dataset rpool/root-unencrypted-copy for manual rollback
  --recover-root       restore unencrypted rpool/ROOT from temporary copy or snapshot
EOF
  exit 1
}

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------
diagnostic_checks() {
  _con "=== pve-encrypt diagnostics ==="
  _con "PASS_FILE: ${PASS_FILE:-<not-set>}"

  if [ -n "${PASS_FILE:-}" ]; then
    if [ -f "$PASS_FILE" ]; then
      _con "PASS_FILE: present ($(wc -c <"$PASS_FILE" 2>/dev/null || echo '?') bytes)"
    else
      _con "PASS_FILE: *** MISSING ***"
    fi
  fi

  printf '\nUtility availability:\n'
  for cmd in zfs zpool modprobe awk sed grep mount umount blkid realpath; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  %-12s OK\n' "$cmd"
    else
      printf '  %-12s *** MISSING ***\n' "$cmd"
    fi
  done

  printf '\nZFS pool status:\n'
  if command -v zpool >/dev/null 2>&1; then
    zpool list 2>/dev/null || printf '  (zpool list failed)\n'
  else
    printf '  zpool: not available\n'
  fi

  printf '\nZFS datasets (first 20):\n'
  if command -v zfs >/dev/null 2>&1; then
    zfs list -H -o name,used,avail,encryption 2>/dev/null | head -n 20 || printf '  (zfs list failed)\n'
  else
    printf '  zfs: not available\n'
  fi

  printf '\n/proc/mounts (first 30):\n'
  sed -n '1,30p' /proc/mounts 2>/dev/null || true

  _con "=== end diagnostics ==="
}

# ---------------------------------------------------------------------------
# Pool import
# ---------------------------------------------------------------------------
import_pool_if_needed() {
  _con "Checking pool ${POOL}..."
  if zpool list -H "$POOL" >/dev/null 2>&1; then
    _ok "Pool ${POOL} already imported"
    return 0
  fi
  _con "Pool not imported - loading zfs module..."
  modprobe zfs >/dev/null 2>&1 || true
  _con "Running: zpool import -N -f ${POOL}"
  if zpool import -N -f "$POOL"; then
    _ok "Pool ${POOL} imported"
  else
    die "zpool import failed for ${POOL}"
  fi
}

# ---------------------------------------------------------------------------
# Recovery
# ---------------------------------------------------------------------------
restore_root_from_copy_or_snapshot() {
  local child="" child_name="" target=""
  local restore_src="" restore_copy="${POOL}/root-recovery-copy"
  local rec_snap="recover-${TS}"
  local size="" n=0 child_count=0

  _step 1 4 "Import pool and locate restore source"
  import_pool_if_needed

  if zfs list -H "$TEMP_ROOT" >/dev/null 2>&1; then
    size=$(_ds_size "$TEMP_ROOT")
    _ok "Temporary copy found: ${TEMP_ROOT} (used: ${size})"
    restore_src="$TEMP_ROOT"
  else
    _con "No temporary copy found - falling back to snapshot"
    [ -n "$SNAPSHOT_NAME" ] || detect_snapshot_if_missing
    zfs list -H "${SOURCE_ROOT}@${SNAPSHOT_NAME}" >/dev/null 2>&1 || \
      die "snapshot not found for recovery: ${SOURCE_ROOT}@${SNAPSHOT_NAME}"
    size=$(_ds_size "${SOURCE_ROOT}@${SNAPSHOT_NAME}")
    _con "Snapshot: ${SOURCE_ROOT}@${SNAPSHOT_NAME} (size: ${size})"

    if zfs list -H "$restore_copy" >/dev/null 2>&1; then
      _con "Removing stale recovery copy: ${restore_copy}"
      zfs destroy -r "$restore_copy"
    fi
    _step 2 4 "Clone snapshot into recovery copy (size: ${size}) - may take minutes"
    _con "Running: zfs send -v -R | zfs recv  -- please wait..."
    zfs send -v -R "${SOURCE_ROOT}@${SNAPSHOT_NAME}" 2>/dev/console | zfs recv -u -F "$restore_copy"
    _ok "Recovery copy created: ${restore_copy}"
    restore_src="$restore_copy"
  fi

  _step 2 4 "Snapshot restore source"
  _con "Creating: ${restore_src}@${rec_snap}"
  zfs snapshot -r "${restore_src}@${rec_snap}"
  _ok "Snapshot created"

  _step 3 4 "Recreate unencrypted ${SOURCE_ROOT}"
  if zfs list -H "$SOURCE_ROOT" >/dev/null 2>&1; then
    _con "Destroying existing ${SOURCE_ROOT}..."
    zfs destroy -r "$SOURCE_ROOT"
    _ok "${SOURCE_ROOT} destroyed"
  fi
  _con "Creating ${SOURCE_ROOT} (unencrypted, mountpoint=/rpool/ROOT, canmount=off)"
  zfs create -o mountpoint="/rpool/ROOT" -o canmount=off "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} created"

  _step 4 4 "Restore children into ${SOURCE_ROOT}"
  child_count=$(zfs list -H -r -d 1 -o name "$restore_src" | grep -c "." || true)
  _con "Datasets to restore: ~${child_count}"

  zfs list -H -r -d 1 -o name "$restore_src" | while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ "$child" = "$restore_src" ] && continue
    n=$((n + 1))
    child_name="${child##*/}"
    target="${SOURCE_ROOT}/${child_name}"
    size=$(_ds_size "${child}@${rec_snap}")
    _con "  [${n}] Restoring ${child_name} (${size}) -> ${target}  please wait..."
    zfs send -v -R "${child}@${rec_snap}" 2>/dev/console | zfs recv -u -F "$target"
    _ok "  [${n}] ${child_name} restored"
  done

  _con "Verifying boot dataset: ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
  zfs list -H "${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}" >/dev/null 2>&1 || \
    die "expected boot dataset missing after recovery: ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
  _ok "Boot dataset present"

  _con "Setting: zpool set bootfs=${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED} ${POOL}"
  zpool set bootfs="${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}" "$POOL"
  _ok "bootfs set -> ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"

  if [ "$restore_src" = "$restore_copy" ]; then
    _con "Cleaning up recovery copy: ${restore_copy}"
    zfs destroy -r "$restore_copy" >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
validate_passfile_layout() {
  local pass_real="$1" rel="" remainder=""
  case "$pass_real" in
    /mnt/*/*) ;;
    *) die "PASS_FILE must be under /mnt/<dir>/<file>: ${pass_real}" ;;
  esac
  rel="${pass_real#/mnt/}"
  remainder="${rel#*/}"
  [ -n "$remainder" ] || die "invalid PASS_FILE filename: ${pass_real}"
  case "$remainder" in
    */*) die "PASS_FILE must be in first-level /mnt subdirectory only: ${pass_real}" ;;
    *) ;;
  esac
}

confirm_or_abort() {
  local prompt="$1" answer=""
  if [ "$AUTO_YES" -eq 1 ]; then
    _con "Auto-confirmed: ${prompt}"
    return 0
  fi
  if [ ! -t 0 ]; then
    die "interactive confirmation required (re-run with --yes)"
  fi
  printf '%s [y/N]: ' "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) die "aborted by user" ;;
  esac
}

detect_snapshot_if_missing() {
  [ -n "$SNAPSHOT_NAME" ] && return 0
  _con "Auto-detecting latest pre-root-encrypt snapshot..."
  SNAPSHOT_NAME="$(zfs list -H -t snapshot -o name -s creation \
    | awk -v d="${SOURCE_ROOT}@" '$1 ~ "^" d "pre-root-encrypt-" {name=$1} END {sub(/^.*@/, "", name); print name}')"
  [ -n "$SNAPSHOT_NAME" ] || die "no pre-root-encrypt snapshot found; pass --snapshot <name>"
  _ok "Detected snapshot: ${SOURCE_ROOT}@${SNAPSHOT_NAME}"
}

validate_preflight() {
  _step 0 6 "Pre-flight checks"

  _con "Checking required commands..."
  need_cmd awk
  need_cmd modprobe
  need_cmd zfs
  need_cmd zpool
  _ok "Required commands present"

  [ "$(id -u)" -eq 0 ] || die "run as root"

  if command -v realpath >/dev/null 2>&1; then
    validate_passfile_layout "$(realpath "$PASS_FILE" 2>/dev/null || printf '%s' "$PASS_FILE")"
  else
    validate_passfile_layout "$PASS_FILE"
  fi
  [ -f "$PASS_FILE" ] || die "passphrase file not found: $PASS_FILE"
  [ -s "$PASS_FILE" ] || die "passphrase file is empty: $PASS_FILE"
  [ -r "$PASS_FILE" ] || die "passphrase file is not readable: $PASS_FILE"
  _ok "Passphrase file valid: ${PASS_FILE}"

  import_pool_if_needed

  zfs list -H "$SOURCE_ROOT" >/dev/null 2>&1 || die "missing source dataset: $SOURCE_ROOT"
  _ok "Source dataset present: ${SOURCE_ROOT}"

  detect_snapshot_if_missing
  zfs list -H "${SOURCE_ROOT}@${SNAPSHOT_NAME}" >/dev/null 2>&1 || \
    die "snapshot not found: ${SOURCE_ROOT}@${SNAPSHOT_NAME}"
  _ok "Snapshot found: ${SOURCE_ROOT}@${SNAPSHOT_NAME}"

  if zfs list -H "$TEMP_ROOT" >/dev/null 2>&1; then
    die "temporary dataset already exists: $TEMP_ROOT (destroy it first, or system is in a bad partial state)"
  fi

  local enc
  enc="$(zfs get -H -o value encryption "$SOURCE_ROOT")"
  _con "Encryption status of ${SOURCE_ROOT}: ${enc}"
  [ "$enc" = "off" ] || die "${SOURCE_ROOT} already encrypted (encryption=${enc})"
  _ok "Pre-flight checks passed"
}

# ---------------------------------------------------------------------------
# Apply steps
# ---------------------------------------------------------------------------
clone_unencrypted_root() {
  local size
  size=$(_ds_size "${SOURCE_ROOT}@${SNAPSHOT_NAME}")
  _step 1 6 "Clone unencrypted ROOT to temp dataset"
  _con "Source: ${SOURCE_ROOT}@${SNAPSHOT_NAME}  size: ${size}"
  _con "Target: ${TEMP_ROOT}"
  _con "Running: zfs send -v -R | zfs recv  -- this may take several minutes..."
  zfs send -v -R "${SOURCE_ROOT}@${SNAPSHOT_NAME}" 2>/dev/console | zfs recv -u -F "$TEMP_ROOT"
  _ok "Clone completed: ${TEMP_ROOT} (used: $(zfs get -H -o value used "$TEMP_ROOT" 2>/dev/null || echo '?'))"
}

create_encrypted_root() {
  _step 2 6 "Destroy unencrypted ${SOURCE_ROOT}"
  _con "NOTE: ${TEMP_ROOT} is the safety copy for rollback"
  zfs destroy -r "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} destroyed"

  _step 3 6 "Create encrypted ${SOURCE_ROOT}"
  _con "Encryption: aes-256-gcm  keyformat: passphrase"
  _con "The next two prompts come from ZFS and set the new passphrase for ${SOURCE_ROOT}."
  _con "IMPORTANT: enter exactly the same passphrase stored in ${PASS_FILE}."
  zfs create \
    -o encryption=aes-256-gcm \
    -o keyformat=passphrase \
    -o keylocation="prompt" \
    -o mountpoint="/rpool/ROOT" \
    -o canmount=off \
    "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} created (encrypted)"

  _con "Validating the entered passphrase against: ${PASS_FILE}"
  zfs unload-key "$SOURCE_ROOT" >/dev/null 2>&1 || die "unable to unload encryption key for validation"
  if zfs load-key -L "file://${PASS_FILE}" "$SOURCE_ROOT"; then
    _ok "Encryption key validated and loaded from PASS_FILE"
  else
    die "passphrase entered at ZFS prompt does not match ${PASS_FILE}"
  fi
}

restore_children_into_encrypted_root() {
  local child="" child_name="" target="" size="" n=0

  _step 4 6 "Snapshot temp copy and restore children into encrypted ROOT"
  _con "Creating snapshot: ${TEMP_ROOT}@${COPY_SNAP}"
  zfs snapshot -r "${TEMP_ROOT}@${COPY_SNAP}"
  _ok "Snapshot created"

  zfs list -H -r -d 1 -o name "$TEMP_ROOT" | while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ "$child" = "$TEMP_ROOT" ] && continue
    n=$((n + 1))
    child_name="${child##*/}"
    target="${SOURCE_ROOT}/${child_name}"
    size=$(_ds_size "${child}@${COPY_SNAP}")
    _con "  [${n}] Restoring ${child_name}  size: ${size}  -> ${target}"
    _con "  Running: zfs send -v -R | zfs recv -x encryption  -- please wait..."
    zfs send -v -R "${child}@${COPY_SNAP}" 2>/dev/console | zfs recv -u -F -x encryption "$target"
    _ok "  [${n}] ${child_name} restored"
  done
}

finalize_bootfs() {
  _step 5 6 "Finalize: set pool bootfs"
  _con "Checking: ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
  zfs list -H "${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}" >/dev/null 2>&1 || \
    die "expected boot dataset missing after restore: ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
  _ok "Boot dataset present"
  _con "Setting: zpool set bootfs=${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED} ${POOL}"
  zpool set bootfs="${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}" "$POOL"
  _ok "bootfs -> ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
}

cleanup_copy_if_requested() {
  _step 6 6 "Cleanup temp dataset"
  if [ "$KEEP_COPY" -eq 1 ]; then
    _con "Keeping temp dataset for rollback: ${TEMP_ROOT}"
    return 0
  fi
  _con "Destroying: ${TEMP_ROOT}"
  zfs destroy -r "$TEMP_ROOT"
  _ok "Temp dataset destroyed"
}

wait_for_completion_confirmation() {
  local mode="$1" answer=""

  while :; do
    printf '\n============================================================\n'
    printf '  CONFIRM NEXT ACTION\n'
    printf '============================================================\n'
    printf 'Press Enter to continue. If launched by the initramfs auto-apply hook,\n'
    printf 'the system will reboot immediately after this confirmation.\n'
    printf 'Type shell to open an emergency shell.\n'
    printf 'Confirmation (%s): ' "$mode" >/dev/console
    read -r answer </dev/console
    case "$answer" in
      "")
        _ok "Confirmation received"
        return 0
        ;;
      shell)
        /bin/sh </dev/console >/dev/console 2>&1
        ;;
      *)
        _con "Invalid input. Press Enter to continue or type shell."
        ;;
    esac
  done
}

print_summary() {
  printf '\n============================================================\n'
  printf '  ROOT ENCRYPTION APPLY COMPLETED SUCCESSFULLY\n'
  printf '============================================================\n'
  printf 'Snapshot used:   %s@%s\n' "$SOURCE_ROOT" "$SNAPSHOT_NAME"
  printf 'Pool bootfs:     %s/%s\n' "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf 'Passphrase file: %s\n' "$PASS_FILE"
  printf '\nPost-boot verification:\n'
  printf '  zfs get encryption,encryptionroot,keystatus %s %s/%s\n' \
    "$SOURCE_ROOT" "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf '  zpool get bootfs %s\n' "$POOL"
  printf '  proxmox-boot-tool status\n'
  printf '============================================================\n'
  _con "APPLY COMPLETED SUCCESSFULLY"
  wait_for_completion_confirmation "apply"
}

print_recovery_summary() {
  printf '\n============================================================\n'
  printf '  ROOT RECOVERY COMPLETED SUCCESSFULLY\n'
  printf '============================================================\n'
  printf 'Pool bootfs: %s/%s\n' "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  [ -n "$SNAPSHOT_NAME" ] && printf 'Snapshot:    %s@%s\n' "$SOURCE_ROOT" "$SNAPSHOT_NAME"
  printf '\nPost-boot verification:\n'
  printf '  zfs get encryption,encryptionroot,keystatus %s\n' "$SOURCE_ROOT"
  printf '  zpool get bootfs %s\n' "$POOL"
  printf '============================================================\n'
  _con "RECOVERY COMPLETED"
  wait_for_completion_confirmation "recovery"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --keep-copy) KEEP_COPY=1; shift ;;
    --recover-root) RECOVERY_MODE=1; shift ;;
    --snapshot)
      [ "$#" -ge 2 ] || die "--snapshot requires a value"
      SNAPSHOT_NAME="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    --*) die "unknown option: $1" ;;
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

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
if [ "$RECOVERY_MODE" -eq 1 ]; then
  _con "=== pve-encrypt RECOVERY MODE ==="
  diagnostic_checks
  need_cmd awk
  need_cmd modprobe
  need_cmd zfs
  need_cmd zpool
  [ "$(id -u)" -eq 0 ] || die "run as root"
  if [ -n "$PASS_FILE" ]; then
    if command -v realpath >/dev/null 2>&1; then
      validate_passfile_layout "$(realpath "$PASS_FILE" 2>/dev/null || printf '%s' "$PASS_FILE")"
    else
      validate_passfile_layout "$PASS_FILE"
    fi
  fi
  confirm_or_abort "Restore ${SOURCE_ROOT} from temporary copy or snapshot?"
  restore_root_from_copy_or_snapshot
  print_recovery_summary
  exit 0
fi

[ -n "$PASS_FILE" ] || usage

_con "=== pve-encrypt APPLY MODE ==="
diagnostic_checks
validate_preflight
confirm_or_abort "Encrypt ${SOURCE_ROOT} from initramfs using snapshot ${SOURCE_ROOT}@${SNAPSHOT_NAME}?"
clone_unencrypted_root
create_encrypted_root
restore_children_into_encrypted_root
finalize_bootfs
cleanup_copy_if_requested
print_summary
