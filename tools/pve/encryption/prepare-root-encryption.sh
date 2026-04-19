#!/usr/bin/env bash
set -Eeuo pipefail

# prepare-root-encryption.sh
#
# Online preparation helper for encrypting rpool/ROOT on Proxmox hosts that use
# proxmox-boot-tool. This script is intentionally conservative and does NOT
# perform the offline initramfs migration step. It only validates prerequisites
# and prepares artifacts needed by apply-root-encryption-initramfs.sh.
#
# Usage:
#   ./prepare-root-encryption.sh <PASS_FILE> [--yes] [--skip-snapshot] [--unlock-method <usb|dropbear|both>] [--install-dropbear]

PASS_FILE=""
AUTO_YES=0
SKIP_SNAPSHOT=0
KEY_MOUNT_POINT=""
UNLOCK_METHOD=""
INSTALL_DROPBEAR=0
DROPBEAR_PORT=4748
SOURCE_ROOT="rpool/ROOT"
POOL="rpool"
ROOT_CHILD="rpool/ROOT/pve-1"
SNAP_PREFIX="pre-root-encrypt"
TS="$(date +%Y%m%d-%H%M%S)"
WORKDIR="/root/root-encrypt-plan-${TS}"
PLAN_FILE="${WORKDIR}/PLAN.txt"
SNAP_NAME="${SNAP_PREFIX}-${TS}"
SNAP_FULL="${SOURCE_ROOT}@${SNAP_NAME}"
INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"
INITRAMFS_MODULES_FILE="/etc/initramfs-tools/modules"
DROPBEAR_CONF="/etc/dropbear/initramfs/dropbear.conf"
DROPBEAR_AUTH_KEYS="/etc/dropbear/initramfs/authorized_keys"
USB_UNLOCK_HOOK="/etc/initramfs-tools/scripts/local-top/zfs-root-usb-key-unlock"
GRUB_CUSTOM_FILE="/etc/grub.d/40_custom"
BACKUP_DIR="${WORKDIR}/file-backups"
CHECKLIST_FILE="${WORKDIR}/CHECKLIST.txt"
BACKUP_COUNT=0
USB_SOURCE_DEVICE=""
USB_LOCATOR_TYPE=""
USB_LOCATOR_VALUE=""
USB_PARTUUID=""
BACKUP_KERNEL_PATH=""
BACKUP_INITRD_PATH=""
BOOT_ENTRY_STATUS="not-configured"
USB_FS_TYPE=""

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
  prepare-root-encryption.sh <PASS_FILE> [--yes] [--skip-snapshot] [--unlock-method <usb|dropbear|both>] [--install-dropbear]

Options:
  --yes                 non-interactive confirmation
  --skip-snapshot       do not create a new rpool/ROOT recursive snapshot
  --unlock-method MODE  root unlock strategy in initramfs: usb, dropbear, both
  --install-dropbear    install missing dropbear-initramfs package automatically

PASS_FILE requirements:
  - must be a full path under /mnt/<first-level-dir>/<file>
  - example: /mnt/_USB_PENDRIVE_KEY/miapasswordzfs.txt
  - for usb/both mode the script auto-detects mountpoint and partition UUID
    from PASS_FILE and configures initramfs mount/unlock automatically
EOF
  exit 1
}

backup_file() {
  local src="$1"
  local rel_path=""
  local dest=""
  [ -n "$src" ] || return 0
  [ -e "$src" ] || return 0
  case "$src" in
    /*) ;;
    *) return 0 ;;
  esac
  rel_path="${src#/}"
  dest="${BACKUP_DIR}/${rel_path}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  BACKUP_COUNT=$((BACKUP_COUNT + 1))
}

validate_passfile_layout() {
  local pass_real="$1"
  local rel=""
  local first=""
  local remainder=""

  case "$pass_real" in
    /mnt/*/*) ;;
    *) die "PASS_FILE must be under /mnt/<dir>/<file>: ${pass_real}" ;;
  esac
  rel="${pass_real#/mnt/}"
  first="${rel%%/*}"
  remainder="${rel#*/}"
  [ -n "$first" ] || die "invalid PASS_FILE mount dir: ${pass_real}"
  [ -n "$remainder" ] || die "invalid PASS_FILE filename: ${pass_real}"
  case "$remainder" in
    */*) die "PASS_FILE must be in first-level /mnt subdirectory only: ${pass_real}" ;;
    *) ;;
  esac
}

unlock_method_uses_usb() {
  [ "$UNLOCK_METHOD" = "usb" ] || [ "$UNLOCK_METHOD" = "both" ]
}

unlock_method_uses_dropbear() {
  [ "$UNLOCK_METHOD" = "dropbear" ] || [ "$UNLOCK_METHOD" = "both" ]
}

select_unlock_method_if_needed() {
  local answer=""
  if [ -n "$UNLOCK_METHOD" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    die "unlock method required in non-interactive mode (use --unlock-method usb|dropbear|both)"
  fi

  printf 'Choose unlock method for rpool/ROOT [usb/dropbear/both]: '
  read -r answer
  case "$answer" in
    usb|dropbear|both) UNLOCK_METHOD="$answer" ;;
    *) die "invalid unlock method: ${answer}" ;;
  esac
}

set_dropbear_options_line() {
  local opts="DROPBEAR_OPTIONS=\"-p ${DROPBEAR_PORT} -s -j -k\""
  mkdir -p "$(dirname "$DROPBEAR_CONF")"
  backup_file "$DROPBEAR_CONF"
  if [ -f "$DROPBEAR_CONF" ] && grep -q '^DROPBEAR_OPTIONS=' "$DROPBEAR_CONF"; then
    sed -i "s|^DROPBEAR_OPTIONS=.*|${opts}|" "$DROPBEAR_CONF"
  else
    printf '%s\n' "$opts" >>"$DROPBEAR_CONF"
  fi
}

ensure_module_line() {
  local module="$1"
  backup_file "$INITRAMFS_MODULES_FILE"
  touch "$INITRAMFS_MODULES_FILE"
  if ! grep -Fxq "$module" "$INITRAMFS_MODULES_FILE"; then
    printf '%s\n' "$module" >>"$INITRAMFS_MODULES_FILE"
  fi
}

detect_usb_locator_from_passfile() {
  local pass_real=""
  local source_dev=""
  local source_mnt=""
  local detected_uuid=""

  if ! unlock_method_uses_usb; then
    return 0
  fi

  pass_real="$(realpath "$PASS_FILE" 2>/dev/null || printf '%s' "$PASS_FILE")"
  validate_passfile_layout "$pass_real"
  source_dev="$(findmnt -n -o SOURCE -T "$PASS_FILE" 2>/dev/null || true)"
  source_mnt="$(findmnt -n -o TARGET -T "$PASS_FILE" 2>/dev/null || true)"
  [ -n "$source_dev" ] || die "unable to detect source device from PASS_FILE: ${PASS_FILE}"
  [ -n "$source_mnt" ] || die "unable to detect source mountpoint from PASS_FILE: ${PASS_FILE}"
  USB_SOURCE_DEVICE="$source_dev"
  KEY_MOUNT_POINT="$source_mnt"

  detected_uuid="$(blkid -s UUID -o value "$source_dev" 2>/dev/null || true)"
  [ -n "$detected_uuid" ] || die "unable to extract filesystem UUID from ${source_dev}"
  USB_LOCATOR_TYPE="uuid"
  USB_LOCATOR_VALUE="$detected_uuid"
  USB_PARTUUID="$(blkid -s PARTUUID -o value "$source_dev" 2>/dev/null || true)"

  case "$pass_real" in
    "${KEY_MOUNT_POINT}"/*) ;;
    *) die "PASS_FILE must be under detected mountpoint ${KEY_MOUNT_POINT} (current: ${pass_real})" ;;
  esac
}

write_usb_unlock_hook() {
  local root_dataset="$SOURCE_ROOT"
  local pass_file="$PASS_FILE"
  local key_mount_point="$KEY_MOUNT_POINT"
  local key_locator_type="$USB_LOCATOR_TYPE"
  local key_locator_value="$USB_LOCATOR_VALUE"

  if ! unlock_method_uses_usb; then
    return 0
  fi

  [ -n "$key_locator_value" ] || die "missing UUID locator for USB unlock hook"
  backup_file "$USB_UNLOCK_HOOK"

  mkdir -p "$(dirname "$USB_UNLOCK_HOOK")"
  cat <<EOF >"$USB_UNLOCK_HOOK"
#!/bin/sh

PREREQ=""
prereqs() {
  echo "\$PREREQ"
}

case "\$1" in
  prereqs)
    prereqs
    exit 0
    ;;
esac

ROOT_DATASET="${root_dataset}"
PASS_FILE="${pass_file}"
KEY_MOUNT_POINT="${key_mount_point}"
KEY_LOCATOR_TYPE="${key_locator_type}"
KEY_LOCATOR_VALUE="${key_locator_value}"

KEY_DEVICE=""
case "\$KEY_LOCATOR_TYPE" in
  uuid) KEY_DEVICE="/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE" ;;
  *) exit 0 ;;
esac

[ -b "\$KEY_DEVICE" ] || exit 0
mkdir -p "\$KEY_MOUNT_POINT"
mount -o ro "\$KEY_DEVICE" "\$KEY_MOUNT_POINT" >/dev/null 2>&1 || exit 0

if [ -f "\$PASS_FILE" ]; then
  zfs load-key -L "file://\$PASS_FILE" "\$ROOT_DATASET" >/dev/null 2>&1 || true
fi

umount "\$KEY_MOUNT_POINT" >/dev/null 2>&1 || true
exit 0
EOF
  chmod 0755 "$USB_UNLOCK_HOOK"
}

create_backup_boot_entry() {
  local kernel_ver=""
  local kernel_src=""
  local initrd_src=""
  local kernel_cmdline=""
  local boot_backup_dir="/boot/pve-root-encrypt-backup"

  kernel_ver="$(uname -r)"
  kernel_src="/boot/vmlinuz-${kernel_ver}"
  initrd_src="/boot/initrd.img-${kernel_ver}"
  [ -f "$kernel_src" ] || return 0
  [ -f "$initrd_src" ] || return 0
  mkdir -p "$boot_backup_dir"

  BACKUP_KERNEL_PATH="${boot_backup_dir}/vmlinuz-${kernel_ver}-${TS}"
  BACKUP_INITRD_PATH="${boot_backup_dir}/initrd.img-${kernel_ver}-${TS}"
  cp -a "$kernel_src" "$BACKUP_KERNEL_PATH"
  cp -a "$initrd_src" "$BACKUP_INITRD_PATH"

  if [ -f /etc/kernel/cmdline ] && [ -s /etc/kernel/cmdline ]; then
    kernel_cmdline="$(cat /etc/kernel/cmdline)"
  else
    kernel_cmdline="root=ZFS=${ROOT_CHILD} boot=zfs"
  fi

  backup_file "$GRUB_CUSTOM_FILE"
  mkdir -p "$(dirname "$GRUB_CUSTOM_FILE")"
  [ -f "$GRUB_CUSTOM_FILE" ] || touch "$GRUB_CUSTOM_FILE"

  local begin_marker="# >>> pve-root-encrypt-backup-entry >>>"
  local end_marker="# <<< pve-root-encrypt-backup-entry <<<"
  local tmp_custom=""
  tmp_custom="$(mktemp)"
  awk -v b="$begin_marker" -v e="$end_marker" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$GRUB_CUSTOM_FILE" >"$tmp_custom"
  mv -f "$tmp_custom" "$GRUB_CUSTOM_FILE"

  cat <<EOF >>"$GRUB_CUSTOM_FILE"

${begin_marker}
menuentry 'Proxmox root-encrypt backup initrd (${TS})' {
  linux ${BACKUP_KERNEL_PATH} ${kernel_cmdline}
  initrd ${BACKUP_INITRD_PATH}
}
${end_marker}
EOF

  if ! command -v update-grub >/dev/null 2>&1; then
    die "update-grub not found; cannot materialize static boot entry from ${GRUB_CUSTOM_FILE}"
  fi
  backup_file "/boot/grub/grub.cfg"
  update-grub >/dev/null 2>&1 || die "update-grub failed while creating backup boot entry"
  BOOT_ENTRY_STATUS="configured-40_custom"
}

write_checklist() {
  local snapshot_status="created"
  if [ "$SKIP_SNAPSHOT" -eq 1 ]; then
    snapshot_status="skipped-by-request"
  fi
  mkdir -p "$WORKDIR"
  cat <<EOF >"$CHECKLIST_FILE"
Root encryption prepare checklist

Timestamp: ${TS}
Unlock method: ${UNLOCK_METHOD}

[x] Environment validation
[x] Snapshot prep: ${snapshot_status}
[x] Modified file backups: ${BACKUP_COUNT}
[x] Initramfs rebuilt: update-initramfs -u -k all
[x] Proxmox boot refresh: proxmox-boot-tool refresh
[x] Backup initrd entry: ${BOOT_ENTRY_STATUS}

USB details:
- Source device: ${USB_SOURCE_DEVICE:-<not-set>}
- Locator type: ${USB_LOCATOR_TYPE:-<not-set>}
- Locator value: ${USB_LOCATOR_VALUE:-<not-set>}
- PARTUUID (informational): ${USB_PARTUUID:-<not-set>}
- Key mountpoint: ${KEY_MOUNT_POINT}
- USB filesystem: ${USB_FS_TYPE:-<not-set>}

Dropbear details:
- Config: ${DROPBEAR_CONF}
- Authorized keys: ${DROPBEAR_AUTH_KEYS}
EOF
}

configure_usb_prereqs() {
  local pass_real=""
  local module_mode=""

  if ! unlock_method_uses_usb; then
    return 0
  fi

  [ -n "$USB_LOCATOR_VALUE" ] || die "usb unlock requires UUID locator extracted from PASS_FILE"
  pass_real="$(realpath "$PASS_FILE" 2>/dev/null || printf '%s' "$PASS_FILE")"
  case "$pass_real" in
    "${KEY_MOUNT_POINT}"/*) ;;
    *) die "usb unlock requires PASS_FILE under ${KEY_MOUNT_POINT} (current: ${pass_real})" ;;
  esac

  USB_FS_TYPE="$(findmnt -n -o FSTYPE -T "$PASS_FILE" 2>/dev/null || true)"
  [ -n "$USB_FS_TYPE" ] || die "unable to detect filesystem type for PASS_FILE mount"

  [ -f "$INITRAMFS_CONF" ] || die "missing ${INITRAMFS_CONF}"
  module_mode="$(awk -F= '/^MODULES=/{gsub(/"/,"",$2); print $2}' "$INITRAMFS_CONF" | tail -n1)"
  if [ "$module_mode" != "most" ]; then
    die "${INITRAMFS_CONF} has MODULES=${module_mode:-<unset>}; set MODULES=most for USB unlock reliability"
  fi

  ensure_module_line usb-storage
  ensure_module_line uas
  ensure_module_line sd_mod
  case "$USB_FS_TYPE" in
    exfat|vfat|ext4|xfs|btrfs)
      ensure_module_line "$USB_FS_TYPE"
      ;;
    *)
      die "unsupported/unhandled USB filesystem for initramfs module auto-setup: ${USB_FS_TYPE}"
      ;;
  esac

  write_usb_unlock_hook
}

configure_dropbear_prereqs() {
  if ! unlock_method_uses_dropbear; then
    return 0
  fi

  if ! dpkg-query -W -f='${Status}' dropbear-initramfs 2>/dev/null | grep -q 'install ok installed'; then
    if [ "$INSTALL_DROPBEAR" -eq 1 ]; then
      apt update
      apt install -y --no-install-recommends dropbear-initramfs
    else
      die "dropbear-initramfs not installed. Re-run with --install-dropbear or install manually: apt install --no-install-recommends dropbear-initramfs"
    fi
  fi

  set_dropbear_options_line
  if [ ! -s "$DROPBEAR_AUTH_KEYS" ]; then
    die "${DROPBEAR_AUTH_KEYS} is missing/empty. Add SSH public key (recommended forced command: zfsunlock)"
  fi
}

rebuild_initramfs_and_refresh_boot() {
  create_backup_boot_entry
  update-initramfs -u -k all
  proxmox-boot-tool refresh
  proxmox-boot-tool status >/dev/null 2>&1 || die "proxmox-boot-tool status failed after refresh"
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

validate_environment() {
  need_cmd awk
  need_cmd apt
  need_cmd blkid
  need_cmd cp
  need_cmd dirname
  need_cmd dpkg-query
  need_cmd findmnt
  need_cmd grep
  need_cmd head
  need_cmd mktemp
  need_cmd mkdir
  need_cmd pveversion
  need_cmd proxmox-boot-tool
  need_cmd realpath
  need_cmd sed
  need_cmd stat
  need_cmd tail
  need_cmd uname
  need_cmd update-initramfs
  need_cmd zfs
  need_cmd zpool

  [ "$(id -u)" -eq 0 ] || die "run as root"
  [ -f "$PASS_FILE" ] || die "passphrase file not found: $PASS_FILE"
  [ -s "$PASS_FILE" ] || die "passphrase file is empty: $PASS_FILE"
  chmod 600 "$PASS_FILE"

  zfs list -H "$POOL" >/dev/null 2>&1 || die "pool not found: $POOL"
  zfs list -H "$SOURCE_ROOT" >/dev/null 2>&1 || die "dataset not found: $SOURCE_ROOT"
  zfs list -H "$ROOT_CHILD" >/dev/null 2>&1 || die "dataset not found: $ROOT_CHILD"

  local root_enc
  root_enc="$(zfs get -H -o value encryption "$SOURCE_ROOT")"
  [ "$root_enc" = "off" ] || die "${SOURCE_ROOT} already encrypted (encryption=${root_enc})"

  local pass_real
  pass_real="$(realpath "$PASS_FILE" 2>/dev/null || printf '%s' "$PASS_FILE")"
  validate_passfile_layout "$pass_real"
  case "$pass_real" in
    /rpool/*|/rpool)
      die "passphrase file must not be inside /rpool (${pass_real})"
      ;;
  esac

  # Ensure proxmox-boot-tool is operational before any risky changes.
  proxmox-boot-tool status >/dev/null 2>&1 || die "proxmox-boot-tool status failed"

  case "$UNLOCK_METHOD" in
    usb|dropbear|both) ;;
    "") ;;
    *) die "invalid --unlock-method '${UNLOCK_METHOD}' (expected usb|dropbear|both)" ;;
  esac
}

create_snapshot() {
  if [ "$SKIP_SNAPSHOT" -eq 1 ]; then
    printf 'Skipping snapshot creation (--skip-snapshot)\n'
    return 0
  fi
  printf 'Creating recursive snapshot: %s\n' "$SNAP_FULL"
  zfs snapshot -r "$SNAP_FULL"
}

print_initramfs_howto() {
  printf 'HOWTO - Run apply from initramfs shell\n'
  printf '1. Reboot the host and open the boot menu.\n'
  printf '2. Select current Proxmox entry and press e to edit kernel args.\n'
  printf '3. Temporarily remove root=... and boot=zfs from the kernel line.\n'
  printf '4. Boot with Ctrl+X (or F10) to drop to initramfs shell.\n'
  printf '5. Verify USB key is available under /mnt and PASS_FILE exists:\n'
  printf '   ls -l "%s"\n' "$PASS_FILE"
  printf '6. Run apply command:\n'
  printf '   bash tools/pve/encryption/apply-root-encryption-initramfs.sh "%s" --snapshot "%s" --yes\n' "$PASS_FILE" "$SNAP_NAME"
  printf '7. When completed, reboot the host.\n'
}

write_plan() {
  mkdir -p "$WORKDIR"
  cat <<EOF >"$PLAN_FILE"
Root encryption prep complete.

Timestamp:         ${TS}
Pool:              ${POOL}
Source root:       ${SOURCE_ROOT}
Root child:        ${ROOT_CHILD}
Passphrase file:   ${PASS_FILE}
Snapshot:          ${SNAP_FULL}
Unlock method:     ${UNLOCK_METHOD}
Key mountpoint:    ${KEY_MOUNT_POINT}
Key UUID:          ${USB_LOCATOR_VALUE:-<not-set>}
Key PARTUUID:      ${USB_PARTUUID:-<not-set>}
USB filesystem:    ${USB_FS_TYPE:-<not-set>}
Source device:     ${USB_SOURCE_DEVICE:-<not-set>}
Locator selected:  ${USB_LOCATOR_TYPE:-<not-set>}=${USB_LOCATOR_VALUE:-<not-set>}
Dropbear conf:     ${DROPBEAR_CONF}
Dropbear keys:     ${DROPBEAR_AUTH_KEYS}
USB unlock hook:   ${USB_UNLOCK_HOOK}
Backups dir:       ${BACKUP_DIR}
Checklist file:    ${CHECKLIST_FILE}
Backup kernel:     ${BACKUP_KERNEL_PATH:-<not-set>}
Backup initrd:     ${BACKUP_INITRD_PATH:-<not-set>}
Boot backup entry: ${BOOT_ENTRY_STATUS}

Important:
- Next step must run from initramfs shell (or equivalent rescue shell), not from
  normal booted rootfs.
- Use apply-root-encryption-initramfs.sh with this snapshot.

Suggested offline command:
  bash tools/pve/encryption/apply-root-encryption-initramfs.sh "${PASS_FILE}" --snapshot "${SNAP_NAME}" --yes

Initramfs/boot actions completed by prepare script:
  update-initramfs -u -k all
  proxmox-boot-tool refresh

Post-boot checks:
  zfs get encryption,encryptionroot,keystatus rpool/ROOT rpool/ROOT/pve-1
  zpool get bootfs rpool
  proxmox-boot-tool status
EOF

  {
    printf '\n'
    print_initramfs_howto
  } >>"$PLAN_FILE"
}

print_summary() {
  printf '\nPreparation complete.\n'
  printf 'Plan file: %s\n' "$PLAN_FILE"
  if [ "$SKIP_SNAPSHOT" -eq 0 ]; then
    printf 'Snapshot:  %s\n' "$SNAP_FULL"
  fi
  printf 'Unlock method: %s\n' "$UNLOCK_METHOD"
  printf 'Key UUID:      %s\n' "${USB_LOCATOR_VALUE:-<not-set>}"
  printf 'Key PARTUUID:  %s\n' "${USB_PARTUUID:-<not-set>}"
  printf 'Key mountpoint:%s\n' " ${KEY_MOUNT_POINT}"
  printf 'USB FS type:   %s\n' "${USB_FS_TYPE:-<not-set>}"
  printf 'Source device: %s\n' "${USB_SOURCE_DEVICE:-<not-set>}"
  printf 'Locator used:  %s=%s\n' "${USB_LOCATOR_TYPE:-<not-set>}" "${USB_LOCATOR_VALUE:-<not-set>}"
  printf 'File backups:  %s (files: %s)\n' "$BACKUP_DIR" "$BACKUP_COUNT"
  printf 'Checklist:     %s\n' "$CHECKLIST_FILE"
  printf 'Backup kernel: %s\n' "${BACKUP_KERNEL_PATH:-<not-set>}"
  printf 'Backup initrd: %s\n' "${BACKUP_INITRD_PATH:-<not-set>}"
  printf 'Boot entry:    %s\n' "$BOOT_ENTRY_STATUS"
  if unlock_method_uses_dropbear; then
    printf 'Dropbear conf: %s\n' "$DROPBEAR_CONF"
    printf 'Dropbear keys: %s\n' "$DROPBEAR_AUTH_KEYS"
  fi
  printf '\n'
  print_initramfs_howto
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --skip-snapshot) SKIP_SNAPSHOT=1; shift ;;
    --unlock-method)
      [ "$#" -ge 2 ] || die "--unlock-method requires a value"
      UNLOCK_METHOD="$2"
      shift 2
      ;;
    --install-dropbear)
      INSTALL_DROPBEAR=1
      shift
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

select_unlock_method_if_needed
validate_environment
detect_usb_locator_from_passfile
confirm_or_abort "Prepare root dataset encryption for ${SOURCE_ROOT}? This is a high-risk operation."
configure_usb_prereqs
configure_dropbear_prereqs
rebuild_initramfs_and_refresh_boot
create_snapshot
write_checklist
write_plan
print_summary
