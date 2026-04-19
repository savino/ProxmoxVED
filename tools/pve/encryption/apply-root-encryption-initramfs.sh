#!/usr/bin/env bash
set -Eeuo pipefail

# apply-root-encryption-initramfs.sh
#
# Offline helper meant to be run from initramfs/rescue shell to encrypt
# rpool/ROOT while rootfs is not mounted.
#
# High-level flow:
# 1) import pool and validate source layout
# 2) clone unencrypted ROOT into a temporary dataset
# 3) destroy unencrypted rpool/ROOT
# 4) create encrypted rpool/ROOT
# 5) copy children from temporary dataset back into encrypted ROOT
# 6) set rpool bootfs and print verification commands
#
# Usage:
#   ./apply-root-encryption-initramfs.sh <PASS_FILE> [--snapshot <name>] [--yes] [--keep-copy]

PASS_FILE=""
AUTO_YES=0
KEEP_COPY=0
SNAPSHOT_NAME=""

POOL="rpool"
SOURCE_ROOT="rpool/ROOT"
TEMP_ROOT="rpool/root-unencrypted-copy"
ROOT_CHILD_EXPECTED="pve-1"
TS="$(date +%Y%m%d-%H%M%S)"
COPY_SNAP="reenc-${TS}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

usage() {
  cat <<'EOF' >&2
Usage:
  apply-root-encryption-initramfs.sh <PASS_FILE> [--snapshot <name>] [--yes] [--keep-copy]

Options:
  --snapshot NAME      source snapshot name on rpool/ROOT (without dataset prefix)
  --yes                non-interactive confirmation
  --keep-copy          keep temporary dataset rpool/root-unencrypted-copy for manual rollback

PASS_FILE requirements:
  - full path under /mnt/<first-level-dir>/<file>
  - example: /mnt/_USB_PENDRIVE_KEY/miapasswordzfs.txt
  - when running from initramfs shell, ensure USB is mounted and PASS_FILE exists
EOF
  exit 1
}

validate_passfile_layout() {
  local pass_real="$1"
  local rel=""
  local remainder=""

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
  local prompt="$1"
  local answer=""
  if [ "$AUTO_YES" -eq 1 ]; then
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

import_pool_if_needed() {
  if zpool list -H "$POOL" >/dev/null 2>&1; then
    return 0
  fi
  modprobe zfs >/dev/null 2>&1 || true
  zpool import -N -f "$POOL"
}

detect_snapshot_if_missing() {
  if [ -n "$SNAPSHOT_NAME" ]; then
    return 0
  fi
  SNAPSHOT_NAME="$(zfs list -H -t snapshot -o name -s creation \
    | awk -v d="${SOURCE_ROOT}@" '$1 ~ "^" d "pre-root-encrypt-" {name=$1} END {sub(/^.*@/, "", name); print name}')"
  [ -n "$SNAPSHOT_NAME" ] || die "no snapshot detected; pass --snapshot <name>"
}

validate_preflight() {
  need_cmd awk
  need_cmd modprobe
  need_cmd zfs
  need_cmd zpool
  need_cmd realpath

  [ "$(id -u)" -eq 0 ] || die "run as root"
  validate_passfile_layout "$(realpath "$PASS_FILE" 2>/dev/null || printf '%s' "$PASS_FILE")"
  [ -f "$PASS_FILE" ] || die "passphrase file not found: $PASS_FILE"
  [ -s "$PASS_FILE" ] || die "passphrase file is empty: $PASS_FILE"
  chmod 600 "$PASS_FILE"

  import_pool_if_needed
  zfs list -H "$SOURCE_ROOT" >/dev/null 2>&1 || die "missing source dataset: $SOURCE_ROOT"

  detect_snapshot_if_missing
  zfs list -H "${SOURCE_ROOT}@${SNAPSHOT_NAME}" >/dev/null 2>&1 || \
    die "snapshot not found: ${SOURCE_ROOT}@${SNAPSHOT_NAME}"

  if zfs list -H "$TEMP_ROOT" >/dev/null 2>&1; then
    die "temporary dataset already exists: $TEMP_ROOT (destroy it first)"
  fi

  local enc
  enc="$(zfs get -H -o value encryption "$SOURCE_ROOT")"
  [ "$enc" = "off" ] || die "${SOURCE_ROOT} already encrypted (encryption=${enc})"
}

clone_unencrypted_root() {
  printf 'Cloning %s@%s into %s\n' "$SOURCE_ROOT" "$SNAPSHOT_NAME" "$TEMP_ROOT"
  zfs send -R "${SOURCE_ROOT}@${SNAPSHOT_NAME}" | zfs recv -u -F "$TEMP_ROOT"
}

create_encrypted_root() {
  printf 'Destroying unencrypted %s\n' "$SOURCE_ROOT"
  zfs destroy -r "$SOURCE_ROOT"

  printf 'Creating encrypted %s\n' "$SOURCE_ROOT"
  zfs create \
    -o encryption=aes-256-gcm \
    -o keyformat=passphrase \
    -o keylocation="prompt" \
    -o mountpoint="/rpool/ROOT" \
    -o canmount=off \
    "$SOURCE_ROOT"

  if [ -f "$PASS_FILE" ]; then
    zfs load-key -L "file://${PASS_FILE}" "$SOURCE_ROOT" >/dev/null 2>&1 || true
  fi
}

restore_children_into_encrypted_root() {
  local child=""
  local child_name=""
  local target=""

  printf 'Creating recursive snapshot on copy dataset: %s@%s\n' "$TEMP_ROOT" "$COPY_SNAP"
  zfs snapshot -r "${TEMP_ROOT}@${COPY_SNAP}"

  while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ "$child" = "$TEMP_ROOT" ] && continue
    child_name="${child##*/}"
    target="${SOURCE_ROOT}/${child_name}"
    printf 'Restoring child %s -> %s\n' "$child" "$target"
    zfs send -R "${child}@${COPY_SNAP}" | zfs recv -u -F "$target"
  done < <(zfs list -H -r -d 1 -o name "$TEMP_ROOT")
}

finalize_bootfs() {
  local bootfs_target="${SOURCE_ROOT}/${ROOT_CHILD_EXPECTED}"
  zfs list -H "$bootfs_target" >/dev/null 2>&1 || \
    die "expected boot dataset missing after restore: $bootfs_target"
  zpool set bootfs="$bootfs_target" "$POOL"
}

cleanup_copy_if_requested() {
  if [ "$KEEP_COPY" -eq 1 ]; then
    printf 'Keeping temporary dataset for rollback: %s\n' "$TEMP_ROOT"
    return 0
  fi
  printf 'Destroying temporary dataset: %s\n' "$TEMP_ROOT"
  zfs destroy -r "$TEMP_ROOT"
}

print_summary() {
  printf '\nROOT encryption apply completed.\n'
  printf 'Source snapshot used: %s@%s\n' "$SOURCE_ROOT" "$SNAPSHOT_NAME"
  printf 'Pool bootfs:          %s/%s\n' "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf 'Passphrase file:      %s\n' "$PASS_FILE"
  printf '\nRun after normal boot:\n'
  printf '  zfs get encryption,encryptionroot,keystatus %s %s/%s\n' "$SOURCE_ROOT" "$SOURCE_ROOT" "$ROOT_CHILD_EXPECTED"
  printf '  zpool get bootfs %s\n' "$POOL"
  printf '  proxmox-boot-tool status\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --keep-copy) KEEP_COPY=1; shift ;;
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

[ -n "$PASS_FILE" ] || usage

validate_preflight
confirm_or_abort "Encrypt ${SOURCE_ROOT} from initramfs using snapshot ${SOURCE_ROOT}@${SNAPSHOT_NAME}?"
clone_unencrypted_root
create_encrypted_root
restore_children_into_encrypted_root
finalize_bootfs
cleanup_copy_if_requested
print_summary
