#!/usr/bin/env bash
set -euo pipefail

# install-encryption-services.sh
# Installs the encryption-related helper scripts and systemd unit templates
# onto the local Proxmox host paths and enables the USB-based load-key service.
# Behavior:
#  - if a destination file exists it is backed up to DEST.bak.TIMESTAMP
#  - prompts interactively before overwriting unless --yes is provided

DEST_SCRIPT=/usr/local/sbin/zfs-load-lxc-keys.sh
DEST_UNIT1=/etc/systemd/system/zfs-load-lxc-keys.service
DEST_UNIT2=/etc/systemd/system/zfs-load-all-keys-from-usb.service
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

AUTO_YES=0
TS=$(date +%Y%m%d-%H%M%S)

usage() {
	local ec="${1:-1}"
	cat <<EOF >&2
Usage: install-encryption-services.sh [--yes] [--service=global|ct|both] [--help]

Options:
	--yes                non-interactive; backup and overwrite existing files
	--service=TYPE       which service(s) to install: global (USB unlock), ct (per-CT), both (default)
	--help               show this help
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

# enable the USB-based loader if present

case "$SERVICE_TYPE" in
	global|both)
		if [ "$INST_UNIT2" -eq 1 ]; then
			printf 'Enabling %s\n' "$(basename "$DEST_UNIT2")"
			if ! systemctl enable --now "$(basename "$DEST_UNIT2")"; then
				printf 'WARNING: failed to enable/start %s; check: systemctl status %s\n' "$(basename "$DEST_UNIT2")" "$(basename "$DEST_UNIT2")" >&2
			fi
		fi
		;;&
	ct|both)
		if [ "$INST_UNIT1" -eq 1 ]; then
			printf 'To enable legacy per-dataset helper now run:\n  systemctl enable --now %s\n' "$(basename "$DEST_UNIT1")"
		fi
		;;
esac

printf 'Done.\n'
exit 0
