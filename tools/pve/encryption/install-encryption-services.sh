#!/usr/bin/env bash
set -euo pipefail

# install-encryption-services.sh
# Installs the encryption-related helper scripts and systemd unit templates
# onto the local Proxmox host paths and enables the USB-based load-key service.
# Behavior:
#  - if a destination file exists it is backed up to DEST.bak.TIMESTAMP
#  - prompts interactively before overwriting unless --yes is provided
#  - enables USB load-key unit for boot; does not start it unless --now

DEST_SCRIPT=/usr/local/sbin/zfs-load-lxc-keys.sh
DEST_UNIT1=/etc/systemd/system/zfs-load-lxc-keys.service
DEST_UNIT2=/etc/systemd/system/zfs-load-all-keys-from-usb.service
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

AUTO_YES=0
START_NOW=0
TS=$(date +%Y%m%d-%H%M%S)

usage() {
	local ec="${1:-1}"
	cat <<EOF >&2
Usage: install-encryption-services.sh [--yes] [--now] [--service=global|ct|both] [--help]

Options:
	--yes                non-interactive; backup and overwrite existing files
	--now                after enable, run systemctl start on the USB load-key unit (optional)
	--service=TYPE       which service(s) to install: global (USB unlock), ct (per-CT), both (default)
	--help               show this help

Default: USB unit is enabled for boot via systemctl enable only (no immediate load-key on host).
EOF
	exit "$ec"
}

if [ "$#" -eq 0 ]; then
	usage 0
fi

SERVICE_TYPE="both"
for arg in "$@"; do
  case "$arg" in
    --yes) AUTO_YES=1 ;;
    --now) START_NOW=1 ;;
    --service=*) SERVICE_TYPE="${arg#--service=}" ;;
		-h|--help) usage 0 ;;
		*) usage 1 ;;
  esac
done

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

confirm_or_abort() {
	local prompt="$1"
	if [ "$AUTO_YES" -eq 1 ]; then
		return 0
	fi
	if [ ! -t 0 ]; then
		die "non-interactive shell and --yes not provided"
	fi
	printf '%s [y/N]: ' "$prompt"
	read -r ans
	case "$ans" in
		y|Y|yes|YES) return 0 ;;
		*) return 1 ;;
	esac
}

install_file() {
	local src="$1" dest="$2" mode="${3:-0644}"
	if [ ! -f "$src" ]; then
		die "source file not found: $src"
	fi
	if [ -e "$dest" ]; then
		printf 'Found existing %s\n' "$dest"
		if confirm_or_abort "Backup and overwrite $dest?"; then
			cp -a "$dest" "${dest}.bak.${TS}" || die "failed to backup $dest"
			printf 'Backed up %s -> %s.bak.%s\n' "$dest" "$dest" "$TS"
		else
			printf 'Skipping %s\n' "$dest"
			return 1
		fi
	fi
	cp "$src" "$dest" || die "failed to install $dest"
	chmod "$mode" "$dest" || die "failed to chmod $dest"
	chown root:root "$dest" || die "failed to chown $dest"
	printf 'Installed %s\n' "$dest"
	return 0
}

print_unit_summary() {
	local unit="$1"
	local label="${2:-$unit}"
	if [ ! -f "/etc/systemd/system/$unit" ] && [ ! -f "/lib/systemd/system/$unit" ]; then
		return 0
	fi
	# Use printf -- so the format cannot be parsed as options (e.g. leading ---)
	printf -- '--- %s ---\n' "$label"
	# is-enabled / is-active may be non-zero when disabled/inactive; still capture stdout
	local en st
	en=$(systemctl is-enabled "$unit" 2>/dev/null) || en=unknown
	st=$(systemctl is-active "$unit" 2>/dev/null) || true
	printf 'is-enabled: %s\n' "${en:-unknown}"
	printf 'is-active: %s\n' "${st:-unknown}"
}

configure_usb_load_key_unit() {
	local unit
	unit="$(basename "$DEST_UNIT2")"
	if [ ! -f "$DEST_UNIT2" ]; then
		printf 'No unit file at %s; skipping enable.\n' "$DEST_UNIT2"
		return 1
	fi
	printf 'Enabling %s for boot (no immediate key load; pass --now to start now)\n' "$unit"
	if ! systemctl enable "$unit"; then
		printf 'WARNING: systemctl enable failed for %s\n' "$unit" >&2
		return 1
	fi
	if [ "$START_NOW" -eq 1 ]; then
		printf 'Starting %s now (--now)\n' "$unit"
		if ! systemctl start "$unit"; then
			printf 'WARNING: start failed (e.g. USB not mounted at /mnt/_USB_PENDRIVE_KEY); check: systemctl status %s\n' "$unit" >&2
		fi
	fi
	print_unit_summary "$unit" "$unit"
	return 0
}

# validate SERVICE_TYPE early
case "$SERVICE_TYPE" in
	global|ct|both) ;;
	*) die "unknown service type: $SERVICE_TYPE" ;;
esac

# Proxmox hosts typically run this as root and may not have sudo installed
if [ "$(id -u)" -ne 0 ]; then
	die "run as root (sudo is not used by this installer)"
fi

printf 'Installing encryption helper scripts and services\n'


installed_any=0
INST_UNIT1=0
INST_UNIT2=0

if [ "$SERVICE_TYPE" = "ct" ] || [ "$SERVICE_TYPE" = "both" ]; then
	if install_file "$SCRIPT_DIR/zfs-load-lxc-keys.sh" "$DEST_SCRIPT" 700; then
		installed_any=1
	fi
	if install_file "$SCRIPT_DIR/zfs-load-lxc-keys.service" "$DEST_UNIT1" 644; then
		INST_UNIT1=1; installed_any=1
	fi
fi

if [ "$SERVICE_TYPE" = "global" ] || [ "$SERVICE_TYPE" = "both" ]; then
	if install_file "$SCRIPT_DIR/zfs-load-all-keys-from-usb.service" "$DEST_UNIT2" 644; then
		INST_UNIT2=1; installed_any=1
	fi
fi

if [ "$installed_any" -eq 0 ]; then
	printf 'No files installed or all skipped by user; nothing to do.\n'
	printf 'Done.\n'
	exit 0
fi

systemctl daemon-reload

# Enable USB load-key unit whenever the unit file exists (fresh install or user kept existing file).
case "$SERVICE_TYPE" in
	global|both)
		configure_usb_load_key_unit || true
		;;
esac

case "$SERVICE_TYPE" in
	ct|both)
		if [ -f "$DEST_UNIT1" ]; then
			printf 'Legacy per-CT helper present: %s\n' "$DEST_UNIT1"
			print_unit_summary "$(basename "$DEST_UNIT1")" "$(basename "$DEST_UNIT1")"
			printf 'To enable at boot: systemctl enable %s\n' "$(basename "$DEST_UNIT1")"
			printf 'To enable and run once: systemctl enable --now %s\n' "$(basename "$DEST_UNIT1")"
		fi
		;;
esac

printf 'Done.\n'
exit 0
