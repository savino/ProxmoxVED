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
UNDO_MODE=0

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
  --keep-copy          deprecated (backup copy is now always kept)
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

  # Set canmount=noauto on backup child datasets whose mountpoint is '/'.
  # If left as canmount=on, zfs-mount.service will try to mount the backup at '/'
  # when booting from the encrypted root, causing a mount conflict and boot hang.
  zfs list -H -r -o name,mountpoint "$TEMP_ROOT" 2>/dev/null | while IFS="	" read -r ds mp; do
    if [ "$mp" = "/" ]; then
      zfs set canmount=noauto "$ds" 2>/dev/null || true
      _ok "Set canmount=noauto on backup child: ${ds} (prevents boot mount conflict)"
    fi
  done
}

create_encrypted_root() {
  _step 2 6 "Destroy unencrypted ${SOURCE_ROOT}"
  _con "NOTE: ${TEMP_ROOT} is the safety copy for rollback"
  zfs destroy -r "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} destroyed"

  _step 3 6 "Create encrypted ${SOURCE_ROOT}"
  _con "Encryption: aes-256-gcm  keyformat: passphrase  keylocation: file://${PASS_FILE}"
  _con "Using passphrase file from USB directly (no interactive prompt)."
  zfs create \
    -o encryption=aes-256-gcm \
    -o keyformat=passphrase \
    -o keylocation="file://${PASS_FILE}" \
    -o mountpoint="/rpool/ROOT" \
    -o canmount=off \
    "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} created (encrypted)"

  _con "Validating encryption key using: ${PASS_FILE}"
  zfs unload-key "$SOURCE_ROOT" >/dev/null 2>&1 || die "unable to unload encryption key for validation"
  if zfs load-key -L "file://${PASS_FILE}" "$SOURCE_ROOT"; then
    _ok "Encryption key validated and loaded from PASS_FILE"
  else
    die "unable to load encryption key from ${PASS_FILE}"
  fi
}

# Change keylocation to 'prompt' after validation so that:
# - The USB unlock hook uses explicit -L file://... to load the key at boot
# - If the hook fails, ZFS falls back to an interactive passphrase prompt
#   instead of a cryptic "file not found" error.
set_keylocation_prompt() {
  _con "Setting keylocation=prompt on ${SOURCE_ROOT} (USB hook will use -L override at boot)"
  zfs set keylocation=prompt "$SOURCE_ROOT"
  _ok "keylocation=prompt set on ${SOURCE_ROOT}"
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
  _con "Keeping backup dataset for rollback: ${TEMP_ROOT}"
  _con "To remove it manually after validation, run: zfs destroy -r ${TEMP_ROOT}"
  _ok "Backup dataset retained"
}

# wait_for_console_confirmation TITLE HINT
# Always reads from /dev/console regardless of AUTO_YES - user must confirm.
wait_for_console_confirmation() {
  local title="$1" hint="$2" answer=""

  printf '\n============================================================\n' >/dev/console
  printf '  %s\n' "$title" >/dev/console
  printf '============================================================\n' >/dev/console
  printf '%s\n' "$hint" >/dev/console
  while :; do
    printf 'Press Enter to confirm, or type "shell" for emergency shell: ' >/dev/console
    read -r answer </dev/console
    case "$answer" in
      "")
        _ok "Confirmed: ${title}"
        return 0
        ;;
      shell)
        /bin/sh </dev/console >/dev/console 2>&1
        printf '\n[Back from shell - %s]\n' "$title" >/dev/console
        ;;
      *)
        printf 'Invalid input - press Enter or type "shell".\n' >/dev/console
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Undo encryption: destroy encrypted SOURCE_ROOT, restore from backup copy
# ---------------------------------------------------------------------------
run_undo_encryption() {
  local enc="" restore_src="" undo_snap="undo-${TS}"
  local clone_target="${POOL}/root-undo-restore"
  local child="" child_name="" target="" size="" n=0

  _con "=== pve-encrypt UNDO ENCRYPTION MODE ==="
  diagnostic_checks

  _step 0 5 "Pre-checks"
  need_cmd awk
  need_cmd modprobe
  need_cmd zfs
  need_cmd zpool
  [ "$(id -u)" -eq 0 ] || die "run as root"

  import_pool_if_needed

  zfs list -H "$SOURCE_ROOT" >/dev/null 2>&1 || die "dataset not found: ${SOURCE_ROOT}"
  enc="$(zfs get -H -o value encryption "$SOURCE_ROOT")"
  [ "$enc" != "off" ] || die "${SOURCE_ROOT} is not encrypted (encryption=off) - nothing to undo"
  _ok "${SOURCE_ROOT} is encrypted (${enc}) - will be reversed"

  if zfs list -H "$TEMP_ROOT" >/dev/null 2>&1; then
    size=$(_ds_size "$TEMP_ROOT")
    _ok "Backup copy found: ${TEMP_ROOT} (used: ${size})"
    restore_src="$TEMP_ROOT"
  else
    _con "Backup copy ${TEMP_ROOT} not found - checking pre-encrypt snapshot..."
    detect_snapshot_if_missing
    zfs list -H "${SOURCE_ROOT}@${SNAPSHOT_NAME}" >/dev/null 2>&1 || \
      die "no undo source: ${TEMP_ROOT} absent and no pre-root-encrypt snapshot found"
    size=$(_ds_size "${SOURCE_ROOT}@${SNAPSHOT_NAME}")
    _ok "Pre-encrypt snapshot: ${SOURCE_ROOT}@${SNAPSHOT_NAME} (size: ${size})"
    restore_src="snapshot"
  fi
  _ok "Pre-checks passed"

  wait_for_console_confirmation "UNDO ENCRYPTION - CONFIRM" \
    "Will DESTROY encrypted ${SOURCE_ROOT} and restore unencrypted backup. THIS IS IRREVERSIBLE."

  if [ "$restore_src" = "snapshot" ]; then
    size=$(_ds_size "${SOURCE_ROOT}@${SNAPSHOT_NAME}")
    _step 1 5 "Clone pre-encrypt snapshot into restore copy (size: ${size})"
    if zfs list -H "$clone_target" >/dev/null 2>&1; then
      _con "Removing stale restore copy: ${clone_target}"
      zfs destroy -r "$clone_target"
    fi
    _con "Running: zfs send -v -R | zfs recv -- please wait..."
    zfs send -v -R "${SOURCE_ROOT}@${SNAPSHOT_NAME}" 2>/dev/console | zfs recv -u -F "$clone_target"
    _ok "Restore copy created: ${clone_target}"
    restore_src="$clone_target"
  else
    _step 1 5 "Snapshot restore source"
  fi

  _con "Creating snapshot: ${restore_src}@${undo_snap}"
  zfs snapshot -r "${restore_src}@${undo_snap}"
  _ok "Snapshot created: ${restore_src}@${undo_snap}"

  _step 2 5 "Destroy encrypted ${SOURCE_ROOT}"
  _con "NOTE: restore source ${restore_src} is the safety copy"
  zfs destroy -r "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} destroyed"

  _step 3 5 "Recreate unencrypted ${SOURCE_ROOT}"
  zfs create -o mountpoint="/rpool/ROOT" -o canmount=off "$SOURCE_ROOT"
  _ok "${SOURCE_ROOT} created (unencrypted)"

  _step 4 5 "Restore children into ${SOURCE_ROOT}"
  zfs list -H -r -d 1 -o name "$restore_src" | while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ "$child" = "$restore_src" ] && continue
    n=$((n + 1))
    child_name="${child##*/}"
    target="${SOURCE_ROOT}/${child_name}"
    size=$(_ds_size "${child}@${undo_snap}")
    _con "  [${n}] Restoring ${child_name} (${size}) -> ${target}"
    _con "  Running: zfs send -v -R | zfs recv -- please wait..."
    zfs send -v -R "${child}@${undo_snap}" 2>/dev/console | zfs recv -u -F "$target"
    _ok "  [${n}] ${child_name} restored"
  done

  _step 5 5 "Finalize"
  zfs list -H "${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}" >/dev/null 2>&1 || \
    die "expected boot dataset missing after restore: ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
  _con "Setting: zpool set bootfs=${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED} ${POOL}"
  zpool set bootfs="${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}" "$POOL"
  _ok "bootfs -> ${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"

  if [ "$restore_src" = "$clone_target" ] && zfs list -H "$clone_target" >/dev/null 2>&1; then
    _con "Cleaning up temporary restore copy: ${clone_target}"
    zfs destroy -r "$clone_target" >/dev/null 2>&1 || true
    _ok "Temporary restore copy removed"
  fi

  printf '\n============================================================\n'
  printf '  UNDO ENCRYPTION COMPLETED SUCCESSFULLY\n'
  printf '============================================================\n'
  printf 'Pool bootfs: %s/%s\n' "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf 'Encryption reversed. %s is now unencrypted.\n' "$SOURCE_ROOT"
  printf '\nPost-boot verification:\n'
  printf '  zfs get encryption,encryptionroot,keystatus %s\n' "$SOURCE_ROOT"
  printf '  zpool get bootfs %s\n' "$POOL"
  printf '============================================================\n'
  _con "UNDO ENCRYPTION COMPLETED SUCCESSFULLY"
  wait_for_console_confirmation "UNDO COMPLETED" \
    "Press Enter to allow the initramfs hook to reboot. The system will boot without encryption."
}

print_summary() {
  printf '\n============================================================\n'
  printf '  ROOT ENCRYPTION APPLY COMPLETED SUCCESSFULLY\n'
  printf '============================================================\n'
  printf 'Snapshot used:   %s@%s\n' "$SOURCE_ROOT" "$SNAPSHOT_NAME"
  printf 'Pool bootfs:     %s/%s\n' "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf 'Passphrase file: %s\n' "$PASS_FILE"
  printf 'Backup dataset:  %s (kept for rollback)\n' "$TEMP_ROOT"
  printf '\nManual cleanup (when no longer needed):\n'
  printf '  zfs destroy -r %s\n' "$TEMP_ROOT"
  printf '\nPost-boot verification:\n'
  printf '  zfs get encryption,encryptionroot,keystatus %s %s/%s\n' \
    "$SOURCE_ROOT" "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf '  zpool get bootfs %s\n' "$POOL"
  printf '  proxmox-boot-tool status\n'
  printf '============================================================\n'
  _con "APPLY COMPLETED SUCCESSFULLY"
  wait_for_console_confirmation "APPLY COMPLETED" \
    "Press Enter to allow the initramfs hook to reboot. Type 'shell' to inspect the system first."
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
  wait_for_console_confirmation "RECOVERY COMPLETED" \
    "Press Enter to allow the initramfs hook to reboot. Type 'shell' to inspect the system first."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --keep-copy) KEEP_COPY=1; shift ;;
    --recover-root) RECOVERY_MODE=1; shift ;;
    --undo-encryption) UNDO_MODE=1; shift ;;
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

[ -n "$PASS_FILE" ] || [ "$UNDO_MODE" -eq 1 ] || usage

if [ "$UNDO_MODE" -eq 1 ]; then
  run_undo_encryption
  exit 0
fi

_con "=== pve-encrypt APPLY MODE ==="
diagnostic_checks
validate_preflight
wait_for_console_confirmation "PREFLIGHT PASSED - CONFIRM ENCRYPTION START" \
  "All checks passed for ${SOURCE_ROOT}. Snapshot: ${SOURCE_ROOT}@${SNAPSHOT_NAME}. Press Enter to begin encryption."
clone_unencrypted_root
create_encrypted_root
set_keylocation_prompt
restore_children_into_encrypted_root
finalize_bootfs
cleanup_copy_if_requested
print_summary
