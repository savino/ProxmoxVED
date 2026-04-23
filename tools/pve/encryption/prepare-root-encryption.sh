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
RESTORE_MODE=0
RESTORE_PLAN_DIR=""
UNDO_ENCRYPTION_MODE=0
KEY_MOUNT_POINT=""
UNLOCK_METHOD=""
INSTALL_DROPBEAR=0
DROPBEAR_PORT=4748
SOURCE_ROOT="rpool/ROOT"
POOL="rpool"
ROOT_CHILD="rpool/ROOT/pve-1"
TEMP_ROOT="rpool/root-unencrypted-copy"
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
ZFS_INITRAMFS_LOAD_KEY_HELPER="/etc/zfs/initramfs-tools-load-key"
GRUB_CUSTOM_FILE="/etc/grub.d/40_custom"
BACKUP_DIR="${WORKDIR}/file-backups"
CHECKLIST_FILE="${WORKDIR}/CHECKLIST.txt"
CREATED_PATHS_FILE="${WORKDIR}/created-paths.txt"
STATE_FILE="/root/.root-encrypt-prepare-state"
AUTOMATION_DIR="/etc/pve-root-encrypt"
AUTOMATION_APPLY_FILE="${AUTOMATION_DIR}/apply-root-encryption-initramfs.sh"
INITRAMFS_EMBED_HOOK="/etc/initramfs-tools/hooks/pve-encrypt-embed"
INITRAMFS_AUTO_APPLY_HOOK="/etc/initramfs-tools/scripts/local-top/pve-encrypt-apply"
ESP_ENCRYPT_DIR_REL="/EFI/proxmox/pve-encrypt"
ESP_STATE_FILE_REL="${ESP_ENCRYPT_DIR_REL}/state"
ESP_LOG_FILE_REL="${ESP_ENCRYPT_DIR_REL}/apply.log"
BACKUP_COUNT=0
USB_SOURCE_DEVICE=""
USB_LOCATOR_TYPE=""
USB_LOCATOR_VALUE=""
USB_PARTUUID=""
BACKUP_KERNEL_PATH=""
BACKUP_INITRD_PATH=""
BOOT_ENTRY_STATUS="not-configured"
FALLBACK_COPY_ENTRY_STATUS="not-configured"
USB_FS_TYPE=""
BOOT_LAYOUT="unknown"
BOOT_REFRESH_ACTION="none"
ESP_BACKUP_KERNEL_REL=""
ESP_BACKUP_INITRD_REL=""
SYSTEMD_BOOT_ENTRY_ID=""
STATE_ESP_UUIDS_CSV=""
declare -a ESP_UUIDS=()

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
  prepare-root-encryption.sh --restore [PLAN_DIR] [--yes]
  prepare-root-encryption.sh --undo-encryption [--yes]

Options:
  --yes                 non-interactive confirmation
  --skip-snapshot       do not create a new rpool/ROOT recursive snapshot
  --restore [PLAN_DIR]  restore modified files from latest or selected root-encrypt-plan-* directory
  --undo-encryption     schedule reversal of ZFS encryption on next reboot (requires backup copy or pre-encrypt snapshot)
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

init_workdir() {
  mkdir -p "$WORKDIR"
  mkdir -p "$BACKUP_DIR"
  touch "$CREATED_PATHS_FILE"
}

list_plan_dirs() {
  find /root -maxdepth 1 -type d -name 'root-encrypt-plan-*' 2>/dev/null | sort
}

list_unrestored_plan_dirs() {
  local d=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -f "${d}/.restored" ] && continue
    printf '%s\n' "$d"
  done < <(list_plan_dirs)
}

latest_unrestored_plan_dir() {
  list_unrestored_plan_dirs | tail -n1
}

write_active_state() {
  cat <<EOF >"$STATE_FILE"
STATUS=prepared
PLAN_DIR=${WORKDIR}
TIMESTAMP=${TS}
SNAPSHOT=${SNAP_FULL}
UNLOCK_METHOD=${UNLOCK_METHOD}
EOF
  chmod 0600 "$STATE_FILE"
}

clear_active_state() {
  [ -f "$STATE_FILE" ] || return 0
  rm -f "$STATE_FILE"
}

build_state_esp_uuid_csv() {
  if [ "${#ESP_UUIDS[@]}" -gt 0 ]; then
    STATE_ESP_UUIDS_CSV="${ESP_UUIDS[*]}"
  else
    STATE_ESP_UUIDS_CSV=""
  fi
}

write_state_payload() {
  local target_file="$1"
  local state_value="$2"

  mkdir -p "$(dirname "$target_file")"
  cat <<EOF >"$target_file"
state=${state_value}
pool=${POOL}
source_root=${SOURCE_ROOT}
root_child=${ROOT_CHILD}
pass_file=${PASS_FILE}
snapshot=${SNAP_NAME}
unlock_method=${UNLOCK_METHOD}
timestamp=${TS}
attempts=0
last_error=
plan_dir=${WORKDIR}
log=${ESP_LOG_FILE_REL}
boot_layout=${BOOT_LAYOUT}
esp_uuids=${STATE_ESP_UUIDS_CSV}
EOF
}

write_pending_state_on_boot_targets() {
  local uuid=""
  local mount_dir=""

  build_state_esp_uuid_csv
  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub|proxmox-boot-tool-systemd-boot)
      [ "${#ESP_UUIDS[@]}" -gt 0 ] || die "cannot write pending state: missing ESP UUIDs"
      for uuid in "${ESP_UUIDS[@]}"; do
        mount_dir="/mnt/pve-root-encrypt-state-${uuid}"
        mount_esp_rw_by_uuid "$uuid" "$mount_dir"
        write_state_payload "${mount_dir}${ESP_STATE_FILE_REL}" "pending"
        umount "$mount_dir"
      done
      ;;
    grub|grub-bios|systemd-boot|unknown)
      if mountpoint -q /boot/efi; then
        write_state_payload "/boot/efi${ESP_STATE_FILE_REL}" "pending"
      elif mountpoint -q /efi; then
        write_state_payload "/efi${ESP_STATE_FILE_REL}" "pending"
      else
        die "unable to locate mounted ESP for state file write"
      fi
      ;;
  esac
}

clear_state_from_boot_targets() {
  local uuid=""
  local mount_dir=""

  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub|proxmox-boot-tool-systemd-boot)
      for uuid in "${ESP_UUIDS[@]}"; do
        mount_dir="/mnt/pve-root-encrypt-state-${uuid}"
        mount_esp_rw_by_uuid "$uuid" "$mount_dir"
        rm -f "${mount_dir}${ESP_STATE_FILE_REL}" "${mount_dir}${ESP_LOG_FILE_REL}"
        umount "$mount_dir"
      done
      ;;
    grub|grub-bios|systemd-boot|unknown)
      if mountpoint -q /boot/efi; then
        rm -f "/boot/efi${ESP_STATE_FILE_REL}" "/boot/efi${ESP_LOG_FILE_REL}"
      elif mountpoint -q /efi; then
        rm -f "/efi${ESP_STATE_FILE_REL}" "/efi${ESP_LOG_FILE_REL}"
      fi
      ;;
  esac
}

ensure_prepare_not_already_active() {
  local active_plan=""
  local legacy_plan=""

  if [ -f "$STATE_FILE" ]; then
    active_plan="$(awk -F= '/^PLAN_DIR=/{print $2}' "$STATE_FILE" | tail -n1)"
    die "prepare already active${active_plan:+ (plan: ${active_plan})}. Run --restore first."
  fi

  legacy_plan="$(latest_unrestored_plan_dir)"
  if [ -n "$legacy_plan" ]; then
    die "existing unrestored plan detected (${legacy_plan}). To avoid layered backups, run --restore first."
  fi
}

resolve_restore_plan_dir() {
  local selected=""
  local count=""
  if [ -n "$RESTORE_PLAN_DIR" ]; then
    [ -d "$RESTORE_PLAN_DIR" ] || die "restore plan directory not found: $RESTORE_PLAN_DIR"
    selected="$RESTORE_PLAN_DIR"
  else
    selected="$(latest_unrestored_plan_dir)"
    [ -n "$selected" ] || die "no unrestored plan directory found under /root/root-encrypt-plan-*"
  fi

  count="$(list_unrestored_plan_dirs | wc -l | tr -d ' ')"
  printf 'Detected unrestored prepare plans: %s\n' "$count"
  if [ "$count" -gt 1 ]; then
    printf 'Preselected latest plan: %s\n' "$selected"
  fi
  RESTORE_PLAN_DIR="$selected"
}

remove_created_paths_from_plan() {
  local plan_dir="$1"
  local created_file="${plan_dir}/created-paths.txt"
  local path=""

  [ -f "$created_file" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      /*)
        [ -e "$path" ] || continue
        rm -rf "$path"
        ;;
      *) ;;
    esac
  done <"$created_file"
}

restore_from_plan() {
  local plan_dir="$1"
  local restore_backup_dir="${plan_dir}/file-backups"
  local enc=""

  [ -d "$restore_backup_dir" ] || die "backup directory not found in plan: ${restore_backup_dir}"

  # Safety: if rpool/ROOT is already encrypted the conversion succeeded and the
  # system is running on the encrypted pool.  Restoring the old initramfs/kernel
  # files would make the next boot use an initramfs that tries to mount an
  # unencrypted root that no longer exists, which bricks the system.
  # Direct the user to --undo-encryption instead.
  enc="$(zfs get -H -o value encryption "${SOURCE_ROOT}" 2>/dev/null || printf 'unknown')"
  if [ "$enc" != "off" ] && [ "$enc" != "unknown" ]; then
    die "${SOURCE_ROOT} is already encrypted (encryption=${enc}). The conversion completed successfully. Restoring old initramfs/kernel files would brick the system. Use --undo-encryption to reverse the ZFS encryption instead."
  fi

  confirm_or_abort "Restore files from ${plan_dir}? This will overwrite current files with saved originals"

  cp -a "${restore_backup_dir}/." /
  remove_created_paths_from_plan "$plan_dir"

  detect_boot_layout
  rm -f "$INITRAMFS_EMBED_HOOK" "$INITRAMFS_AUTO_APPLY_HOOK" "$AUTOMATION_APPLY_FILE"
  clear_state_from_boot_targets

  update-initramfs -u -k all
  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub|proxmox-boot-tool-systemd-boot)
      proxmox-boot-tool refresh
      ;;
    grub|grub-bios|unknown)
      if command -v update-grub >/dev/null 2>&1; then
        update-grub >/dev/null 2>&1
      fi
      ;;
    systemd-boot)
      ;;
  esac

  touch "${plan_dir}/.restored"
  clear_active_state
  printf 'Restore completed from plan: %s\n' "$plan_dir"
}

backup_file() {
  local src="$1"
  local rel_path=""
  local dest=""
  [ -n "$src" ] || return 0
  case "$src" in
    /*) ;;
    *) return 0 ;;
  esac
  if [ ! -e "$src" ]; then
    mkdir -p "$WORKDIR"
    touch "$CREATED_PATHS_FILE"
    if ! grep -Fxq "$src" "$CREATED_PATHS_FILE" 2>/dev/null; then
      printf '%s\n' "$src" >>"$CREATED_PATHS_FILE"
    fi
    return 0
  fi
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

create_backup_boot_entry() {
  local kernel_ver=""
  local kernel_src=""
  local initrd_src=""
  local kernel_cmdline=""
  local boot_backup_dir="/boot/pve-root-encrypt-backup"
  local begin_marker="# >>> pve-root-encrypt-backup-entry >>>"
  local end_marker="# <<< pve-root-encrypt-backup-entry <<<"
  local tmp_custom=""
  local first_uuid=""

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
  if [ ! -f "$GRUB_CUSTOM_FILE" ]; then
    touch "$GRUB_CUSTOM_FILE"
  fi
  chmod 0755 "$GRUB_CUSTOM_FILE"

  tmp_custom="$(mktemp)"
  awk -v b="$begin_marker" -v e="$end_marker" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$GRUB_CUSTOM_FILE" >"$tmp_custom"
  mv -f "$tmp_custom" "$GRUB_CUSTOM_FILE"
  chmod 0755 "$GRUB_CUSTOM_FILE"

  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub)
      [ "${#ESP_UUIDS[@]}" -gt 0 ] || die "proxmox-boot-tool GRUB mode detected but no ESP UUIDs found"
      first_uuid="${ESP_UUIDS[0]}"
      ESP_BACKUP_KERNEL_REL="/pve-root-encrypt-backup/vmlinuz-${kernel_ver}-${TS}"
      ESP_BACKUP_INITRD_REL="/pve-root-encrypt-backup/initrd.img-${kernel_ver}-${TS}"
      sync_backup_payload_to_esps "$BACKUP_KERNEL_PATH" "$BACKUP_INITRD_PATH" "$ESP_BACKUP_KERNEL_REL" "$ESP_BACKUP_INITRD_REL"

      cat <<EOF >>"$GRUB_CUSTOM_FILE"

${begin_marker}
menuentry 'Proxmox root-encrypt backup initrd (${TS})' {
  insmod part_gpt
  insmod fat
  search --no-floppy --fs-uuid --set=root ${first_uuid}
  linux ${ESP_BACKUP_KERNEL_REL} ${kernel_cmdline}
  initrd ${ESP_BACKUP_INITRD_REL}
}
${end_marker}
EOF
      BOOT_ENTRY_STATUS="configured-proxmox-grub-esp"
      ;;
    proxmox-boot-tool-systemd-boot)
      [ "${#ESP_UUIDS[@]}" -gt 0 ] || die "proxmox-boot-tool systemd-boot mode detected but no ESP UUIDs found"
      ESP_BACKUP_KERNEL_REL="/EFI/proxmox/root-encrypt-backup-${TS}/vmlinuz-${kernel_ver}"
      ESP_BACKUP_INITRD_REL="/EFI/proxmox/root-encrypt-backup-${TS}/initrd.img-${kernel_ver}"
      SYSTEMD_BOOT_ENTRY_ID="proxmox-root-encrypt-backup-${TS}"
      sync_backup_payload_to_esps "$BACKUP_KERNEL_PATH" "$BACKUP_INITRD_PATH" "$ESP_BACKUP_KERNEL_REL" "$ESP_BACKUP_INITRD_REL"
      write_systemd_boot_entries_to_esps "$SYSTEMD_BOOT_ENTRY_ID" "Proxmox root-encrypt backup initrd (${TS})" "$kernel_ver" "$kernel_cmdline" "$ESP_BACKUP_KERNEL_REL" "$ESP_BACKUP_INITRD_REL"
      BOOT_ENTRY_STATUS="configured-proxmox-systemd-boot-esp"
      ;;
    systemd-boot)
      write_local_systemd_boot_entry "$BACKUP_KERNEL_PATH" "$BACKUP_INITRD_PATH" "$kernel_ver" "$kernel_cmdline"
      BOOT_ENTRY_STATUS="configured-local-systemd-boot"
      ;;
    grub|grub-bios|unknown)
      cat <<EOF >>"$GRUB_CUSTOM_FILE"

${begin_marker}
menuentry 'Proxmox root-encrypt backup initrd (${TS})' {
  linux ${BACKUP_KERNEL_PATH} ${kernel_cmdline}
  initrd ${BACKUP_INITRD_PATH}
}
${end_marker}
EOF
      BOOT_ENTRY_STATUS="configured-40_custom"
      ;;
    *)
      die "unsupported boot layout: ${BOOT_LAYOUT}"
      ;;
  esac

  chmod 0755 "$GRUB_CUSTOM_FILE"
}

create_unencrypted_copy_boot_entry() {
  local fallback_cmdline=""
  local temp_root_child=""
  local fallback_entry_id=""
  local tmp_custom=""
  local begin_marker="# >>> pve-root-encrypt-copy-fallback >>>"
  local end_marker="# <<< pve-root-encrypt-copy-fallback <<<"
  local kernel_ver=""
  local esp_root=""

  # Reuse the backup kernel/initrd already copied by create_backup_boot_entry
  [ -f "${BACKUP_KERNEL_PATH:-}" ] || return 0
  [ -f "${BACKUP_INITRD_PATH:-}" ] || return 0

  kernel_ver="$(uname -r)"
  # The clone preserves child names: rpool/ROOT/pve-1 -> TEMP_ROOT/pve-1
  temp_root_child="${TEMP_ROOT}/${ROOT_CHILD##*/}"
  fallback_cmdline="root=ZFS=${temp_root_child} boot=zfs"
  fallback_entry_id="proxmox-root-encrypt-copy-${TS}"

  # Remove any previous fallback entry from the GRUB custom file
  if [ -f "$GRUB_CUSTOM_FILE" ]; then
    tmp_custom="$(mktemp)"
    awk -v b="$begin_marker" -v e="$end_marker" '
      $0 == b {skip=1; next}
      $0 == e {skip=0; next}
      !skip {print}
    ' "$GRUB_CUSTOM_FILE" >"$tmp_custom"
    mv -f "$tmp_custom" "$GRUB_CUSTOM_FILE"
    chmod 0755 "$GRUB_CUSTOM_FILE"
  fi

  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub)
      cat <<EOF >>"$GRUB_CUSTOM_FILE"

${begin_marker}
menuentry 'Proxmox unencrypted copy fallback (${TS})' {
  insmod part_gpt
  insmod fat
  search --no-floppy --fs-uuid --set=root ${ESP_UUIDS[0]}
  linux ${ESP_BACKUP_KERNEL_REL} ${fallback_cmdline}
  initrd ${ESP_BACKUP_INITRD_REL}
}
${end_marker}
EOF
      chmod 0755 "$GRUB_CUSTOM_FILE"
      FALLBACK_COPY_ENTRY_STATUS="configured-proxmox-grub-esp"
      ;;
    proxmox-boot-tool-systemd-boot)
      write_systemd_boot_entries_to_esps "$fallback_entry_id" "Proxmox unencrypted copy fallback (${TS})" "$kernel_ver" "$fallback_cmdline" "$ESP_BACKUP_KERNEL_REL" "$ESP_BACKUP_INITRD_REL"
      FALLBACK_COPY_ENTRY_STATUS="configured-proxmox-systemd-boot-esp"
      ;;
    systemd-boot)
      if [ -d /boot/efi/loader/entries ]; then
        esp_root="/boot/efi"
      elif [ -d /efi/loader/entries ]; then
        esp_root="/efi"
      else
        FALLBACK_COPY_ENTRY_STATUS="skipped-no-esp"
        return 0
      fi
      # Reuse kernel/initrd already placed by write_local_systemd_boot_entry
      cat <<EOF >"${esp_root}/loader/entries/${fallback_entry_id}.conf"
title   Proxmox unencrypted copy fallback (${TS})
version ${kernel_ver}
options ${fallback_cmdline}
linux   /EFI/proxmox/root-encrypt-backup-${TS}/vmlinuz-${kernel_ver}
initrd  /EFI/proxmox/root-encrypt-backup-${TS}/initrd.img-${kernel_ver}
EOF
      FALLBACK_COPY_ENTRY_STATUS="configured-local-systemd-boot"
      ;;
    grub|grub-bios|unknown)
      cat <<EOF >>"$GRUB_CUSTOM_FILE"

${begin_marker}
menuentry 'Proxmox unencrypted copy fallback (${TS})' {
  linux ${BACKUP_KERNEL_PATH} ${fallback_cmdline}
  initrd ${BACKUP_INITRD_PATH}
}
${end_marker}
EOF
      chmod 0755 "$GRUB_CUSTOM_FILE"
      FALLBACK_COPY_ENTRY_STATUS="configured-40_custom"
      ;;
    *)
      FALLBACK_COPY_ENTRY_STATUS="skipped-unknown-layout"
      ;;
  esac
}

detect_boot_layout() {
  local pbt_status=""

  BOOT_LAYOUT="unknown"
  ESP_UUIDS=()

  if [ -s /etc/kernel/proxmox-boot-uuids ] && command -v proxmox-boot-tool >/dev/null 2>&1; then
    mapfile -t ESP_UUIDS < <(grep -E '^[A-Fa-f0-9-]+$' /etc/kernel/proxmox-boot-uuids)
    pbt_status="$(proxmox-boot-tool status 2>/dev/null || true)"
    if printf '%s' "$pbt_status" | grep -qi 'configured with:.*grub'; then
      BOOT_LAYOUT="proxmox-boot-tool-grub"
      return 0
    fi
    if printf '%s' "$pbt_status" | grep -qi 'configured with:.*systemd-boot'; then
      BOOT_LAYOUT="proxmox-boot-tool-systemd-boot"
      return 0
    fi
    BOOT_LAYOUT="proxmox-boot-tool-grub"
    return 0
  fi

  if [ ! -d /sys/firmware/efi ]; then
    BOOT_LAYOUT="grub-bios"
    return 0
  fi

  if command -v efibootmgr >/dev/null 2>&1; then
    pbt_status="$(efibootmgr -v 2>/dev/null || true)"
    if printf '%s' "$pbt_status" | grep -qi 'systemd-bootx64\.efi'; then
      BOOT_LAYOUT="systemd-boot"
      return 0
    fi
    if printf '%s' "$pbt_status" | grep -qi 'grubx64\.efi\|shimx64\.efi'; then
      BOOT_LAYOUT="grub"
      return 0
    fi
  fi

  if [ -d /boot/efi/loader/entries ] || [ -d /efi/loader/entries ]; then
    BOOT_LAYOUT="systemd-boot"
  else
    BOOT_LAYOUT="grub"
  fi
}

mount_esp_rw_by_uuid() {
  local uuid="$1"
  local mount_dir="$2"

  mkdir -p "$mount_dir"
  mountpoint -q "$mount_dir" && umount "$mount_dir" || true
  mount -o rw "UUID=${uuid}" "$mount_dir"
}

sync_backup_payload_to_esps() {
  local src_kernel="$1"
  local src_initrd="$2"
  local dst_kernel_rel="$3"
  local dst_initrd_rel="$4"
  local uuid=""
  local mount_dir=""

  for uuid in "${ESP_UUIDS[@]}"; do
    mount_dir="/mnt/pve-root-encrypt-esp-${uuid}"
    mount_esp_rw_by_uuid "$uuid" "$mount_dir"
    mkdir -p "${mount_dir}$(dirname "$dst_kernel_rel")"
    mkdir -p "${mount_dir}$(dirname "$dst_initrd_rel")"
    cp -a "$src_kernel" "${mount_dir}${dst_kernel_rel}"
    cp -a "$src_initrd" "${mount_dir}${dst_initrd_rel}"
    umount "$mount_dir"
  done
}

write_systemd_boot_entries_to_esps() {
  local entry_id="$1"
  local title="$2"
  local version="$3"
  local options="$4"
  local linux_rel="$5"
  local initrd_rel="$6"
  local uuid=""
  local mount_dir=""

  for uuid in "${ESP_UUIDS[@]}"; do
    mount_dir="/mnt/pve-root-encrypt-esp-${uuid}"
    mount_esp_rw_by_uuid "$uuid" "$mount_dir"
    mkdir -p "${mount_dir}/loader/entries"
    cat <<EOF >"${mount_dir}/loader/entries/${entry_id}.conf"
title   ${title}
version ${version}
options ${options}
linux   ${linux_rel}
initrd  ${initrd_rel}
EOF
    umount "$mount_dir"
  done
}

write_local_systemd_boot_entry() {
  local kernel_path="$1"
  local initrd_path="$2"
  local kernel_ver="$3"
  local cmdline="$4"
  local esp_root=""
  local entry_id=""

  if [ -d /boot/efi/loader/entries ]; then
    esp_root="/boot/efi"
  elif [ -d /efi/loader/entries ]; then
    esp_root="/efi"
  else
    die "systemd-boot detected but unable to locate mounted ESP loader/entries"
  fi

  entry_id="proxmox-root-encrypt-backup-${TS}"
  mkdir -p "${esp_root}/EFI/proxmox/root-encrypt-backup-${TS}"
  cp -a "$kernel_path" "${esp_root}/EFI/proxmox/root-encrypt-backup-${TS}/vmlinuz-${kernel_ver}"
  cp -a "$initrd_path" "${esp_root}/EFI/proxmox/root-encrypt-backup-${TS}/initrd.img-${kernel_ver}"
  cat <<EOF >"${esp_root}/loader/entries/${entry_id}.conf"
title   Proxmox root-encrypt backup initrd (${TS})
version ${kernel_ver}
options ${cmdline}
linux   /EFI/proxmox/root-encrypt-backup-${TS}/vmlinuz-${kernel_ver}
initrd  /EFI/proxmox/root-encrypt-backup-${TS}/initrd.img-${kernel_ver}
EOF
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
[x] Boot layout detected: ${BOOT_LAYOUT}
[x] Snapshot prep: ${snapshot_status}
[x] Modified file backups: ${BACKUP_COUNT}
[x] Auto-apply hook: ${INITRAMFS_AUTO_APPLY_HOOK}
[x] Initramfs embed hook: ${INITRAMFS_EMBED_HOOK}
[x] ESP state file: ${ESP_STATE_FILE_REL}
[x] Initramfs rebuilt: update-initramfs -u -k all
[x] Boot config refresh: ${BOOT_REFRESH_ACTION}
[x] Backup initrd entry: ${BOOT_ENTRY_STATUS}
[x] Unencrypted copy fallback entry: ${FALLBACK_COPY_ENTRY_STATUS}

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

  write_zfs_initramfs_load_key_helper
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
  create_unencrypted_copy_boot_entry
  update-initramfs -u -k all

  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub|proxmox-boot-tool-systemd-boot)
      proxmox-boot-tool refresh
      proxmox-boot-tool status >/dev/null 2>&1 || die "proxmox-boot-tool status failed after refresh"
      BOOT_REFRESH_ACTION="proxmox-boot-tool refresh"
      ;;
    grub|grub-bios|unknown)
      if command -v update-grub >/dev/null 2>&1; then
        backup_file "/boot/grub/grub.cfg"
        update-grub >/dev/null 2>&1 || die "update-grub failed while creating backup boot entry"
        BOOT_REFRESH_ACTION="update-grub"
      else
        BOOT_REFRESH_ACTION="none (update-grub not found)"
      fi
      ;;
    systemd-boot)
      BOOT_REFRESH_ACTION="none (entry written to mounted ESP loader/entries)"
      ;;
    *)
      die "unsupported boot layout during refresh: ${BOOT_LAYOUT}"
      ;;
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
  need_cmd mount
  need_cmd mktemp
  need_cmd mkdir
  need_cmd pveversion
  need_cmd realpath
  need_cmd sed
  need_cmd stat
  need_cmd tail
  need_cmd umount
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

  detect_boot_layout

  # On proxmox-boot-tool systems ensure the command is healthy before any risky changes.
  if [ "$BOOT_LAYOUT" = "proxmox-boot-tool-grub" ] || [ "$BOOT_LAYOUT" = "proxmox-boot-tool-systemd-boot" ]; then
    need_cmd proxmox-boot-tool
    proxmox-boot-tool status >/dev/null 2>&1 || die "proxmox-boot-tool status failed"
  fi

  case "$UNLOCK_METHOD" in
    usb|dropbear|both) ;;
    "") ;;
    *) die "invalid --unlock-method '${UNLOCK_METHOD}' (expected usb|dropbear|both)" ;;
  esac
}

validate_restore_environment() {
  need_cmd awk
  need_cmd cp
  need_cmd find
  need_cmd mount
  need_cmd rm
  need_cmd sort
  need_cmd tail
  need_cmd tr
  need_cmd umount
  need_cmd update-initramfs
  need_cmd zfs
  need_cmd zpool
  [ "$(id -u)" -eq 0 ] || die "run as root"
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
Root encryption preparation complete.

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
Auto apply hook:   ${INITRAMFS_AUTO_APPLY_HOOK}
Embed hook:        ${INITRAMFS_EMBED_HOOK}
Embedded apply:    ${AUTOMATION_APPLY_FILE}
ESP state file:    ${ESP_STATE_FILE_REL}
ESP log file:      ${ESP_LOG_FILE_REL}
Backups dir:       ${BACKUP_DIR}
Created paths:     ${CREATED_PATHS_FILE}
Checklist file:    ${CHECKLIST_FILE}
Backup kernel:     ${BACKUP_KERNEL_PATH:-<not-set>}
Backup initrd:     ${BACKUP_INITRD_PATH:-<not-set>}
Boot backup entry: ${BOOT_ENTRY_STATUS}
State file:        ${STATE_FILE}

Next steps:
- Reboot the system. The encryption apply process will run automatically in initramfs before root is mounted.
- If the process is interrupted or fails, a recovery menu will appear at boot, allowing you to retry, restore, or open a shell.
- After successful encryption, the system will boot normally.

To revert all changes (restore original files and configuration):
  bash tools/pve/encryption/prepare-root-encryption.sh --restore "${WORKDIR}"

Post-boot checks (after successful encryption):
  zfs get encryption,encryptionroot,keystatus rpool/ROOT rpool/ROOT/pve-1
  zpool get bootfs rpool
  proxmox-boot-tool status
EOF
}

print_summary() {
  printf '\nPreparazione completata.\n'
  printf 'File piano: %s\n' "$PLAN_FILE"
  if [ "$SKIP_SNAPSHOT" -eq 0 ]; then
    printf 'Snapshot:  %s\n' "$SNAP_FULL"
  fi
  printf 'Metodo unlock: %s\n' "$UNLOCK_METHOD"
  printf 'Boot layout:   %s\n' "$BOOT_LAYOUT"
  printf 'Key UUID:      %s\n' "${USB_LOCATOR_VALUE:-<not-set>}"
  printf 'Key PARTUUID:  %s\n' "${USB_PARTUUID:-<not-set>}"
  printf 'Key mountpoint:%s\n' " ${KEY_MOUNT_POINT}"
  printf 'USB FS type:   %s\n' "${USB_FS_TYPE:-<not-set>}"
  printf 'Source device: %s\n' "${USB_SOURCE_DEVICE:-<not-set>}"
  printf 'Locator used:  %s=%s\n' "${USB_LOCATOR_TYPE:-<not-set>}" "${USB_LOCATOR_VALUE:-<not-set>}"
  printf 'Backup file:   %s (files: %s)\n' "$BACKUP_DIR" "$BACKUP_COUNT"
  printf 'Percorsi creati: %s\n' "$CREATED_PATHS_FILE"
  printf 'Auto hook:     %s\n' "$INITRAMFS_AUTO_APPLY_HOOK"
  printf 'Embed hook:    %s\n' "$INITRAMFS_EMBED_HOOK"
  printf 'Embedded apply:%s\n' " ${AUTOMATION_APPLY_FILE}"
  printf 'ESP state file:%s\n' " ${ESP_STATE_FILE_REL}"
  printf 'Checklist:     %s\n' "$CHECKLIST_FILE"
  printf 'Backup kernel: %s\n' "${BACKUP_KERNEL_PATH:-<not-set>}"
  printf 'Backup initrd: %s\n' "${BACKUP_INITRD_PATH:-<not-set>}"
  printf 'Boot entry:    %s\n' "$BOOT_ENTRY_STATUS"
  printf 'Fallback entry:%s\n' " ${FALLBACK_COPY_ENTRY_STATUS}"
  printf 'State file:    %s\n' "$STATE_FILE"
  if unlock_method_uses_dropbear; then
    printf 'Dropbear conf: %s\n' "$DROPBEAR_CONF"
    printf 'Dropbear keys: %s\n' "$DROPBEAR_AUTH_KEYS"
  fi
  printf "\nProssimi passi:\n"
  printf "%s\n" "-- Riavvia il sistema. L'applicazione della cifratura verrà eseguita automaticamente in initramfs prima del mount di root."
  printf "%s\n" "-- In caso di errore o interruzione, apparirà un menu di recovery al boot per riprovare, ripristinare o aprire una shell."
  printf "%s\n" "-- Dopo il successo, il sistema avvierà normalmente."
  printf "\nPer annullare tutte le modifiche (restore):\n"
  printf '  bash tools/pve/encryption/prepare-root-encryption.sh --restore "%s"\n' "$WORKDIR"
  printf "\nDopo il boot, controlla:\n"
  printf '  zfs get encryption,encryptionroot,keystatus rpool/ROOT rpool/ROOT/pve-1\n'
  printf '  zpool get bootfs rpool\n'
  printf '  proxmox-boot-tool status\n'
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
MAX_WAIT=30

_log() { printf '[zfs-usb-unlock] %s\n' "\$*" >/dev/console 2>/dev/null || true; }

case "\$KEY_LOCATOR_TYPE" in
  uuid) ;;
  *) exit 0 ;;
esac

# Wait up to MAX_WAIT seconds for the USB device to appear.
KEY_DEVICE=""
i=0
while [ "\$i" -lt "\$MAX_WAIT" ]; do
  if [ -b "/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE" ]; then
    KEY_DEVICE="/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE"
    break
  fi
  if [ "\$i" -eq 0 ]; then
    _log "Waiting for USB key device (UUID=\$KEY_LOCATOR_VALUE)..."
  fi
  sleep 1
  i=\$((i + 1))
done

if [ -z "\$KEY_DEVICE" ]; then
  _log "USB key device not found after \${MAX_WAIT}s (UUID=\$KEY_LOCATOR_VALUE)"
  exit 0
fi

mkdir -p "\$KEY_MOUNT_POINT"
if ! mount -o ro "\$KEY_DEVICE" "\$KEY_MOUNT_POINT" >/dev/null 2>&1; then
  _log "Failed to mount USB key device \$KEY_DEVICE on \$KEY_MOUNT_POINT"
  exit 0
fi

if [ -f "\$PASS_FILE" ]; then
  _log "USB key file detected at \$PASS_FILE"
else
  _log "Key file not found on USB: \$PASS_FILE"
fi

umount "\$KEY_MOUNT_POINT" >/dev/null 2>&1 || true
exit 0
EOF
  chmod 0755 "$USB_UNLOCK_HOOK"
}

write_zfs_initramfs_load_key_helper() {
  local root_dataset="$SOURCE_ROOT"
  local pass_file="$PASS_FILE"
  local key_mount_point="$KEY_MOUNT_POINT"
  local key_locator_type="$USB_LOCATOR_TYPE"
  local key_locator_value="$USB_LOCATOR_VALUE"
  local usb_fs_type="$USB_FS_TYPE"

  if ! unlock_method_uses_usb; then
    return 0
  fi

  [ -n "$key_locator_value" ] || die "missing UUID locator for ZFS initramfs key helper"
  backup_file "$ZFS_INITRAMFS_LOAD_KEY_HELPER"

  mkdir -p "$(dirname "$ZFS_INITRAMFS_LOAD_KEY_HELPER")"
  cat <<EOF >"$ZFS_INITRAMFS_LOAD_KEY_HELPER"
#!/bin/sh

ROOT_DATASET="${root_dataset}"
PASS_FILE="${pass_file}"
KEY_MOUNT_POINT="${key_mount_point}"
KEY_LOCATOR_TYPE="${key_locator_type}"
KEY_LOCATOR_VALUE="${key_locator_value}"
KEY_FS_TYPE="${usb_fs_type}"
MAX_WAIT=30

_log() { printf '[zfs-initramfs-load-key] %s\n' "\$*" >/dev/console 2>/dev/null || true; }

# ZFS native initramfs calls this helper after pool import.
if [ -n "\${ENCRYPTIONROOT:-}" ] && [ "\$ENCRYPTIONROOT" != "\$ROOT_DATASET" ]; then
  exit 0
fi

if zfs get -H -o value keystatus "\$ROOT_DATASET" 2>/dev/null | grep -q '^available$'; then
  exit 0
fi

case "\$KEY_LOCATOR_TYPE" in
  uuid) ;;
  *) exit 0 ;;
esac

for module in usb-storage uas sd_mod scsi_mod; do
  modprobe "\$module" >/dev/null 2>&1 || true
done
[ -n "\$KEY_FS_TYPE" ] && modprobe "\$KEY_FS_TYPE" >/dev/null 2>&1 || true

KEY_DEVICE=""
i=0
while [ "\$i" -lt "\$MAX_WAIT" ]; do
  if [ -b "/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE" ]; then
    KEY_DEVICE="/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE"
    break
  fi
  if [ "\$i" -eq 0 ]; then
    _log "Waiting for USB key device (UUID=\$KEY_LOCATOR_VALUE)..."
  fi
  sleep 1
  i=\$((i + 1))
done

if [ -z "\$KEY_DEVICE" ]; then
  _log "USB key device not found after \${MAX_WAIT}s (UUID=\$KEY_LOCATOR_VALUE)"
  exit 0
fi

mkdir -p "\$KEY_MOUNT_POINT"
if ! mount -o ro "\$KEY_DEVICE" "\$KEY_MOUNT_POINT" >/dev/null 2>&1; then
  _log "Failed to mount USB key device \$KEY_DEVICE on \$KEY_MOUNT_POINT"
  exit 0
fi

if [ -f "\$PASS_FILE" ]; then
  if zfs load-key -L "file://\$PASS_FILE" "\$ROOT_DATASET" >/dev/null 2>&1; then
    _log "ZFS key loaded successfully for \$ROOT_DATASET"
  else
    _log "zfs load-key failed for \$ROOT_DATASET (wrong passphrase or dataset error)"
  fi
else
  _log "Key file not found on USB: \$PASS_FILE"
fi

umount "\$KEY_MOUNT_POINT" >/dev/null 2>&1 || true
exit 0
EOF
  chmod 0755 "$ZFS_INITRAMFS_LOAD_KEY_HELPER"
}

resolve_apply_script_source() {
  local self_dir=""
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  printf '%s\n' "${self_dir}/apply-root-encryption-initramfs.sh"
}

write_initramfs_embed_hook() {
  backup_file "$INITRAMFS_EMBED_HOOK"
  mkdir -p "$(dirname "$INITRAMFS_EMBED_HOOK")"
  cat <<'EOF' >"$INITRAMFS_EMBED_HOOK"
#!/bin/sh

PREREQ=""
prereqs() {
  echo "$PREREQ"
}

case "$1" in
  prereqs)
    prereqs
    exit 0
    ;;
esac

mkdir -p "${DESTDIR}/root/pve-encrypt"
mkdir -p "${DESTDIR}/scripts/local-top"

cp -a /etc/pve-root-encrypt/apply-root-encryption-initramfs.sh "${DESTDIR}/root/pve-encrypt/apply-root-encryption-initramfs.sh"
chmod 0755 "${DESTDIR}/root/pve-encrypt/apply-root-encryption-initramfs.sh"

cp -a /etc/initramfs-tools/scripts/local-top/pve-encrypt-apply "${DESTDIR}/scripts/local-top/pve-encrypt-apply"
chmod 0755 "${DESTDIR}/scripts/local-top/pve-encrypt-apply"
EOF
  chmod 0755 "$INITRAMFS_EMBED_HOOK"
}

write_initramfs_auto_apply_hook() {
  local key_locator_type="$USB_LOCATOR_TYPE"
  local key_locator_value="$USB_LOCATOR_VALUE"
  local key_partuuid="$USB_PARTUUID"
  local key_fs_type="$USB_FS_TYPE"

  backup_file "$INITRAMFS_AUTO_APPLY_HOOK"
  mkdir -p "$(dirname "$INITRAMFS_AUTO_APPLY_HOOK")"
  cat <<EOF >"$INITRAMFS_AUTO_APPLY_HOOK"
#!/bin/sh

PREREQ="zfs-root-usb-key-unlock"
prereqs() {
  echo "\$PREREQ"
}

case "\$1" in
  prereqs)
    prereqs
    exit 0
    ;;
esac

LOCK_FILE="/run/pve-encrypt-apply.lock"
ESP_MNT="/run/pve-encrypt-esp"
STATE_REL="${ESP_STATE_FILE_REL}"
LOG_REL="${ESP_LOG_FILE_REL}"
ESP_UUIDS="${STATE_ESP_UUIDS_CSV}"
APPLY_SCRIPT="/root/pve-encrypt/apply-root-encryption-initramfs.sh"
TMP_LOG="/tmp/pve-encrypt-apply.log"

STATE=""
POOL=""
SOURCE_ROOT=""
ROOT_CHILD=""
PASS_FILE=""
SNAPSHOT=""
UNLOCK_METHOD=""
TIMESTAMP=""
PLAN_DIR=""
ATTEMPTS=0
LAST_ERROR=""
BOOT_LAYOUT=""
KEY_LOCATOR_TYPE="${key_locator_type}"
KEY_LOCATOR_VALUE="${key_locator_value}"
KEY_PARTUUID="${key_partuuid}"
KEY_FS_TYPE="${key_fs_type}"

msg() {
  echo "[pve-encrypt-apply] \$*"
  printf '%s\n' "[pve-encrypt-apply] \$*" >>"\$TMP_LOG" 2>/dev/null || true
}


is_mounted() {
  # Prefer the mountpoint utility if present; otherwise check /proc/mounts.
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "\$1"
    return \$?
  fi
  grep -q " \$1 " /proc/mounts 2>/dev/null
}

mount_state_esp_rw() {
  local uuid=""
  mkdir -p "\$ESP_MNT"
  for uuid in \$ESP_UUIDS; do
    [ -b "/dev/disk/by-uuid/\$uuid" ] || continue
    if is_mounted "\$ESP_MNT"; then
      umount "\$ESP_MNT" >/dev/null 2>&1 || true
    fi
    if mount -o rw "/dev/disk/by-uuid/\$uuid" "\$ESP_MNT" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

umount_state_esp() { is_mounted "\$ESP_MNT" && umount "\$ESP_MNT" >/dev/null 2>&1 || true; }

restore_tmp_log_from_esp_if_needed() {
  # On subsequent boots in failed/running states, keep the previous attempt log
  # available in /tmp so the recovery menu can show real diagnostics.
  if [ ! -s "\$TMP_LOG" ] && [ -f "\$ESP_MNT\$LOG_REL" ]; then
    cp -a "\$ESP_MNT\$LOG_REL" "\$TMP_LOG" >/dev/null 2>&1 || true
  fi
}

load_usb_modules() {
  local module=""

  for module in usb-storage uas sd_mod scsi_mod; do
    modprobe "\$module" >/dev/null 2>&1 || true
  done

  [ -n "\$KEY_FS_TYPE" ] && modprobe "\$KEY_FS_TYPE" >/dev/null 2>&1 || true
}

resolve_key_device() {
  local dev="" uuid="" partuuid=""

  if [ -n "\$KEY_LOCATOR_VALUE" ] && [ -b "/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE" ]; then
    printf '%s\n' "/dev/disk/by-uuid/\$KEY_LOCATOR_VALUE"
    return 0
  fi

  if [ -n "\$KEY_PARTUUID" ] && [ -b "/dev/disk/by-partuuid/\$KEY_PARTUUID" ]; then
    printf '%s\n' "/dev/disk/by-partuuid/\$KEY_PARTUUID"
    return 0
  fi

  if command -v blkid >/dev/null 2>&1; then
    for dev in /dev/sd* /dev/vd* /dev/nvme*n*p* /dev/mmcblk*p*; do
      [ -b "\$dev" ] || continue
      uuid="\$(blkid -s UUID -o value "\$dev" 2>/dev/null || true)"
      partuuid="\$(blkid -s PARTUUID -o value "\$dev" 2>/dev/null || true)"
      if [ -n "\$KEY_LOCATOR_VALUE" ] && [ "\$uuid" = "\$KEY_LOCATOR_VALUE" ]; then
        printf '%s\n' "\$dev"
        return 0
      fi
      if [ -n "\$KEY_PARTUUID" ] && [ "\$partuuid" = "\$KEY_PARTUUID" ]; then
        printf '%s\n' "\$dev"
        return 0
      fi
    done
  fi

  return 1
}

probe_key_device_by_mount() {
  local dev="" pass_dir=""

  pass_dir="\$(dirname "\$PASS_FILE")"
  mkdir -p "\$pass_dir"

  for dev in /dev/sd[a-z][0-9]* /dev/vd[a-z][0-9]* /dev/nvme*n*p* /dev/mmcblk*p*; do
    [ -b "\$dev" ] || continue

    if is_mounted "\$pass_dir"; then
      umount "\$pass_dir" >/dev/null 2>&1 || true
    fi

    if mount -o ro "\$dev" "\$pass_dir" >/dev/null 2>&1; then
      :
    elif [ -n "\$KEY_FS_TYPE" ] && mount -t "\$KEY_FS_TYPE" -o ro "\$dev" "\$pass_dir" >/dev/null 2>&1; then
      :
    else
      continue
    fi

    if [ -f "\$PASS_FILE" ]; then
      printf '%s\n' "\$dev"
      return 0
    fi

    umount "\$pass_dir" >/dev/null 2>&1 || true
  done

  return 1
}

log_key_device_diagnostics() {
  msg "USB key diagnostics: PASS_FILE=\$PASS_FILE FS=\$KEY_FS_TYPE UUID=\$KEY_LOCATOR_VALUE PARTUUID=\$KEY_PARTUUID"
  if [ -d /dev/disk/by-uuid ]; then
    msg "Available /dev/disk/by-uuid entries:"
    ls -1 /dev/disk/by-uuid >>"\$TMP_LOG" 2>/dev/null || true
  fi
  if [ -d /dev/disk/by-partuuid ]; then
    msg "Available /dev/disk/by-partuuid entries:"
    ls -1 /dev/disk/by-partuuid >>"\$TMP_LOG" 2>/dev/null || true
  fi
  if command -v blkid >/dev/null 2>&1; then
    msg "blkid snapshot:"
    blkid >>"\$TMP_LOG" 2>/dev/null || true
  fi
}

wait_for_passfile() {
  local attempt=1 max_attempts=30

  while [ "\$attempt" -le "\$max_attempts" ]; do
    [ -f "\$PASS_FILE" ] && return 0

    load_usb_modules

    if ensure_passfile_available_once; then
      return 0
    fi

    if [ "\$attempt" -eq 1 ] || [ \$((attempt % 5)) -eq 0 ]; then
      msg "USB key not ready yet (attempt \$attempt/\$max_attempts)"
    fi

    sleep 1
    attempt=\$((attempt + 1))
  done

  log_key_device_diagnostics
  return 1
}

ensure_passfile_available_once() {
  local pass_dir="" key_dev=""

  [ -n "\$PASS_FILE" ] || return 1
  [ -f "\$PASS_FILE" ] && return 0

  pass_dir="\$(dirname "\$PASS_FILE")"
  mkdir -p "\$pass_dir"

  key_dev="\$(resolve_key_device 2>/dev/null || true)"
  if [ -z "\$key_dev" ]; then
    msg "Unable to resolve USB key device by UUID/PARTUUID (UUID=\$KEY_LOCATOR_VALUE PARTUUID=\$KEY_PARTUUID). Trying mount-probe fallback..."
    key_dev="\$(probe_key_device_by_mount 2>/dev/null || true)"
    [ -n "\$key_dev" ] || return 1
    msg "Mount-probe fallback found candidate device: \$key_dev"
    return 0
  fi

  if is_mounted "\$pass_dir"; then
    umount "\$pass_dir" >/dev/null 2>&1 || true
  fi

  if mount -o ro "\$key_dev" "\$pass_dir" >/dev/null 2>&1; then
    :
  elif [ -n "\$KEY_FS_TYPE" ] && mount -t "\$KEY_FS_TYPE" -o ro "\$key_dev" "\$pass_dir" >/dev/null 2>&1; then
    :
  else
    msg "Failed mounting USB device \$key_dev on \$pass_dir"
    return 1
  fi

  if [ -f "\$PASS_FILE" ]; then
    msg "Mounted \$key_dev on \$pass_dir and found PASS_FILE"
    return 0
  fi

  msg "Mounted \$key_dev on \$pass_dir but PASS_FILE still missing: \$PASS_FILE"
  return 1
}

ensure_passfile_available() {
  [ -n "\$PASS_FILE" ] || return 1
  [ -f "\$PASS_FILE" ] && return 0

  wait_for_passfile
}

load_state() {
  local file="\$ESP_MNT\$STATE_REL"
  [ -f "\$file" ] || return 1
  while IFS='=' read -r key value; do
    case "\$key" in
      state) STATE="\$value" ;;
      pool) POOL="\$value" ;;
      source_root) SOURCE_ROOT="\$value" ;;
      root_child) ROOT_CHILD="\$value" ;;
      pass_file) PASS_FILE="\$value" ;;
      snapshot) SNAPSHOT="\$value" ;;
      unlock_method) UNLOCK_METHOD="\$value" ;;
      timestamp) TIMESTAMP="\$value" ;;
      attempts) ATTEMPTS="\$value" ;;
      last_error) LAST_ERROR="\$value" ;;
      plan_dir) PLAN_DIR="\$value" ;;
      boot_layout) BOOT_LAYOUT="\$value" ;;
    esac
  done <"\$file"
  [ -n "\$STATE" ]
}

write_state() {
  local new_state="\$1"
  local new_error="\${2:-}"
  local attempts="\$ATTEMPTS"
  [ "\$new_state" = "running" ] && attempts=\$((attempts + 1))
  mkdir -p "\$ESP_MNT\$(dirname "\$STATE_REL")"
  cat <<STATEEOF >"\$ESP_MNT\$STATE_REL"
state=\$new_state
pool=\$POOL
source_root=\$SOURCE_ROOT
root_child=\$ROOT_CHILD
pass_file=\$PASS_FILE
snapshot=\$SNAPSHOT
unlock_method=\$UNLOCK_METHOD
timestamp=\$TIMESTAMP
attempts=\$attempts
last_error=\$new_error
plan_dir=\$PLAN_DIR
log=\$LOG_REL
boot_layout=\$BOOT_LAYOUT
esp_uuids=\$ESP_UUIDS
STATEEOF
  ATTEMPTS="\$attempts"
  LAST_ERROR="\$new_error"
  STATE="\$new_state"
}

flush_log() {
  mkdir -p "\$ESP_MNT\$(dirname "\$LOG_REL")"
  [ -f "\$TMP_LOG" ] && cp -a "\$TMP_LOG" "\$ESP_MNT\$LOG_REL"
}

open_recovery_menu() {
  local choice="" rc_file="/tmp/.pve_recovery_rc"
  msg "Apply state=\$STATE (error=\$LAST_ERROR)."
  msg "Log: \$TMP_LOG  (also on ESP: \$LOG_REL)"
  while :; do
    echo ""
    echo "pve-encrypt recovery menu"
    echo "1) Attempt ROOT restore from copy/snapshot"
    echo "2) Show apply log"
    echo "3) Open emergency shell"
    echo "4) Reboot"
    printf "Choice [1-4]: "
    read -r choice
    case "\$choice" in
      1)
        msg "Starting recovery - output visible on screen and logged..."
        rm -f "\$rc_file"
        # Run with tee so output appears on screen AND goes to log.
        # Exit code is captured in a temp file because POSIX sh pipeline
        # exits with the exit code of the last command (tee), not apply.
        { "\$APPLY_SCRIPT" "\$PASS_FILE" --snapshot "\$SNAPSHOT" --yes --recover-root; printf '%d' "\$?" >"\$rc_file"; } 2>&1 | tee -a "\$TMP_LOG"
        if [ "\$(cat "\$rc_file" 2>/dev/null)" = "0" ]; then
          write_state "recovered" ""
          flush_log
          umount_state_esp
          msg "Recovery succeeded. Rebooting..."
          reboot -f
          echo b > /proc/sysrq-trigger
        else
          write_state "failed" "recovery_failed"
          flush_log
          msg "Recovery FAILED. Opening emergency shell."
          /bin/sh
        fi
        ;;
      2)
        echo "--- LOG START ---"
        cat "\$TMP_LOG" 2>/dev/null || echo "(log empty)"
        echo "--- LOG END ---"
        ;;
      3) /bin/sh ;;
      4)
        umount_state_esp
        reboot -f
        echo b > /proc/sysrq-trigger
        ;;
      *) msg "Invalid choice." ;;
    esac
  done
}

[ -e "\$LOCK_FILE" ] && exit 0
touch "\$LOCK_FILE"
mount_state_esp_rw || exit 0
load_state || { umount_state_esp; exit 0; }
restore_tmp_log_from_esp_if_needed

APPLY_EXTRA_ARGS=""
case "\$STATE" in
  completed|recovered) umount_state_esp; exit 0 ;;
  running)
    write_state "failed" "interrupted_previous_run"
    flush_log
    open_recovery_menu
    ;;
  failed)
    flush_log
    open_recovery_menu
    ;;
  undo-encryption)
    APPLY_EXTRA_ARGS="--undo-encryption"
    ;;
  pending) ;;
  *) umount_state_esp; exit 0 ;;
esac

if [ ! -x "\$APPLY_SCRIPT" ]; then
  write_state "failed" "apply_script_missing"
  flush_log
  open_recovery_menu
fi

if [ -z "\$APPLY_EXTRA_ARGS" ] && ! ensure_passfile_available; then
  write_state "failed" "pass_file_missing"
  flush_log
  open_recovery_menu
fi

write_state "running" ""
_apply_rc_file="/tmp/.pve_apply_rc"
rm -f "\$_apply_rc_file"
# Fresh apply attempt: start a new per-attempt log file.
rm -f "\$TMP_LOG"
: >"\$TMP_LOG"
# Run apply with tee so output is visible on screen AND logged.
# Exit code is written to a temp file because a POSIX sh pipeline
# returns the exit of the last process (tee), not the apply script.
{ "\$APPLY_SCRIPT" "\$PASS_FILE" --snapshot "\$SNAPSHOT" \${APPLY_EXTRA_ARGS} --yes; printf '%d' "\$?" >"\$_apply_rc_file"; } 2>&1 | tee -a "\$TMP_LOG"
if [ "\$(cat "\$_apply_rc_file" 2>/dev/null)" = "0" ]; then
  if [ -n "\$APPLY_EXTRA_ARGS" ]; then
    write_state "recovered" ""
  else
    write_state "completed" ""
  fi
  flush_log
  umount_state_esp
  msg "Apply succeeded. Rebooting..."
  reboot -f
  echo b > /proc/sysrq-trigger
else
  write_state "failed" "apply_failed"
  flush_log
  open_recovery_menu
fi

umount_state_esp
exit 0
EOF
  chmod 0755 "$INITRAMFS_AUTO_APPLY_HOOK"
}

# ---------------------------------------------------------------------------
# Undo-encryption helpers
# ---------------------------------------------------------------------------

# Overwrite the state= field in all ESP state files to "undo-encryption",
# preserving all other fields from the original prepare run.
write_undo_encryption_state() {
  local uuid="" mount_dir="" state_file_path="" current_state="" tmp=""

  detect_boot_layout
  build_state_esp_uuid_csv

  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub|proxmox-boot-tool-systemd-boot)
      [ "${#ESP_UUIDS[@]}" -gt 0 ] || die "cannot write undo state: no ESP UUIDs found"
      for uuid in "${ESP_UUIDS[@]}"; do
        mount_dir="/mnt/pve-root-encrypt-state-${uuid}"
        mount_esp_rw_by_uuid "$uuid" "$mount_dir"
        state_file_path="${mount_dir}${ESP_STATE_FILE_REL}"
        if [ ! -f "$state_file_path" ]; then
          umount "$mount_dir"
          die "ESP state file not found on UUID=${uuid}: ${state_file_path}. Run prepare first."
        fi
        current_state="$(awk -F= '/^state=/{print $2}' "$state_file_path" | tail -n1)"
        case "$current_state" in
          completed|recovered|failed) ;;
          *) umount "$mount_dir"; die "unexpected state '${current_state}' in ESP state file. Expected completed/recovered/failed." ;;
        esac
        tmp="$(mktemp)"
        sed 's/^state=.*/state=undo-encryption/' "$state_file_path" >"$tmp"
        mv -f "$tmp" "$state_file_path"
        umount "$mount_dir"
        printf 'Wrote undo-encryption state to ESP UUID=%s\n' "$uuid"
      done
      ;;
    grub|grub-bios|systemd-boot|unknown)
      local mnt=""
      if mountpoint -q /boot/efi; then
        mnt="/boot/efi"
      elif mountpoint -q /efi; then
        mnt="/efi"
      else
        die "cannot locate mounted ESP for state file write"
      fi
      state_file_path="${mnt}${ESP_STATE_FILE_REL}"
      [ -f "$state_file_path" ] || die "ESP state file not found: ${state_file_path}. Run prepare first."
      current_state="$(awk -F= '/^state=/{print $2}' "$state_file_path" | tail -n1)"
      case "$current_state" in
        completed|recovered|failed) ;;
        *) die "unexpected state '${current_state}' in ESP state file. Expected completed/recovered/failed." ;;
      esac
      tmp="$(mktemp)"
      sed 's/^state=.*/state=undo-encryption/' "$state_file_path" >"$tmp"
      mv -f "$tmp" "$state_file_path"
      printf 'Wrote undo-encryption state to ESP (%s)\n' "$mnt"
      ;;
  esac
}

run_undo_encryption_prepare() {
  need_cmd sed
  need_cmd update-initramfs
  need_cmd zfs
  need_cmd zpool
  [ "$(id -u)" -eq 0 ] || die "run as root"

  # Validate: SOURCE_ROOT must be encrypted
  zfs list -H "$SOURCE_ROOT" >/dev/null 2>&1 || die "dataset not found: ${SOURCE_ROOT}"
  enc="$(zfs get -H -o value encryption "$SOURCE_ROOT" 2>/dev/null || printf 'unknown')"
  [ "$enc" != "off" ] && [ "$enc" != "unknown" ] || \
    die "${SOURCE_ROOT} is not encrypted (encryption=${enc:-off}) - nothing to undo"
  printf 'rpool/ROOT encryption: %s - confirmed\n' "$enc"

  # Validate: undo source must exist
  if zfs list -H "$TEMP_ROOT" >/dev/null 2>&1; then
    printf 'Backup copy found: %s\n' "$TEMP_ROOT"
  else
    printf 'Backup copy %s not found - checking for pre-encrypt snapshot...\n' "$TEMP_ROOT"
    snap_name="$(zfs list -H -t snapshot -o name -s creation 2>/dev/null | \
      awk -v d="${SOURCE_ROOT}@" '$1 ~ "^" d "pre-root-encrypt-" {name=$1} END {sub(/^.*@/, "", name); print name}')"
    [ -n "$snap_name" ] || \
      die "no undo source found: ${TEMP_ROOT} absent and no pre-root-encrypt-* snapshot exists"
    printf 'Pre-encrypt snapshot found: %s@%s\n' "$SOURCE_ROOT" "$snap_name"
  fi

  # Validate: initramfs apply hook must be in place
  [ -f "$INITRAMFS_AUTO_APPLY_HOOK" ] || \
    die "initramfs apply hook not found: ${INITRAMFS_AUTO_APPLY_HOOK}. Re-run prepare to reinstall hooks first."
  printf 'Initramfs apply hook: %s - found\n' "$INITRAMFS_AUTO_APPLY_HOOK"

  confirm_or_abort "Schedule undo-encryption on next reboot? Will destroy encrypted ${SOURCE_ROOT} and restore from backup."

  # Update the embedded apply script and rebuild initramfs so the
  # --undo-encryption flag is supported by the initramfs-embedded copy.
  apply_source="$(resolve_apply_script_source)"
  [ -f "$apply_source" ] || die "apply script not found: ${apply_source}"
  mkdir -p "$AUTOMATION_DIR"
  cp -a "$apply_source" "$AUTOMATION_APPLY_FILE"
  chmod 0755 "$AUTOMATION_APPLY_FILE"
  printf 'Updated apply script: %s\n' "$AUTOMATION_APPLY_FILE"

  printf 'Rebuilding initramfs to embed updated apply script...\n'
  update-initramfs -u -k all

  detect_boot_layout
  case "$BOOT_LAYOUT" in
    proxmox-boot-tool-grub|proxmox-boot-tool-systemd-boot)
      proxmox-boot-tool refresh
      ;;
    grub|grub-bios|unknown)
      update-grub 2>/dev/null || true
      ;;
  esac

  write_undo_encryption_state

  printf '\nUndo-encryption scheduled.\n'
  printf 'NEXT STEP: Reboot the system.\n'
  printf 'On next boot the initramfs hook will:\n'
  printf '  1. Detect state=undo-encryption\n'
  printf '  2. Destroy the encrypted %s\n' "$SOURCE_ROOT"
  printf '  3. Restore from the unencrypted backup copy/snapshot\n'
  printf '  4. Set bootfs and reboot\n'
  printf 'The system will then boot normally without encryption.\n'
}

install_initramfs_automation_assets() {
  local apply_source=""

  apply_source="$(resolve_apply_script_source)"
  [ -f "$apply_source" ] || die "apply script not found near prepare script: ${apply_source}"
  build_state_esp_uuid_csv

  backup_file "$AUTOMATION_APPLY_FILE"
  mkdir -p "$AUTOMATION_DIR"
  cp -a "$apply_source" "$AUTOMATION_APPLY_FILE"
  chmod 0755 "$AUTOMATION_APPLY_FILE"

  write_initramfs_auto_apply_hook
  write_initramfs_embed_hook
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) AUTO_YES=1; shift ;;
    --skip-snapshot) SKIP_SNAPSHOT=1; shift ;;
    --restore)
      RESTORE_MODE=1
      if [ "$#" -ge 2 ] && [ "${2#--}" = "$2" ]; then
        RESTORE_PLAN_DIR="$2"
        shift 2
      else
        shift
      fi
      ;;
    --undo-encryption)
      UNDO_ENCRYPTION_MODE=1
      shift
      ;;
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

if [ "$RESTORE_MODE" -eq 1 ]; then
  [ -n "$PASS_FILE" ] && die "PASS_FILE must not be provided with --restore"
  validate_restore_environment
  resolve_restore_plan_dir
  restore_from_plan "$RESTORE_PLAN_DIR"
  exit 0
fi

if [ "$UNDO_ENCRYPTION_MODE" -eq 1 ]; then
  [ -n "$PASS_FILE" ] && die "PASS_FILE must not be provided with --undo-encryption"
  run_undo_encryption_prepare
  exit 0
fi

[ -n "$PASS_FILE" ] || usage

select_unlock_method_if_needed
validate_environment
ensure_prepare_not_already_active
detect_usb_locator_from_passfile
confirm_or_abort "Prepare root dataset encryption for ${SOURCE_ROOT}? This is a high-risk operation."
init_workdir
configure_usb_prereqs
configure_dropbear_prereqs
install_initramfs_automation_assets
write_pending_state_on_boot_targets
rebuild_initramfs_and_refresh_boot
create_snapshot
write_checklist
write_plan
write_active_state
print_summary
