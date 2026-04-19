#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

# proxmox-migration-system-report.sh
#
# Read-only system inventory for Proxmox + ZFS migration planning.
# Does not modify the system; only runs inspection commands.
#
# Usage:
#   ./proxmox-migration-system-report.sh [--output PATH.md]
#   ./proxmox-migration-system-report.sh -o /root/report-$(hostname).md

OUT=""
HOST="$(hostname -s 2>/dev/null || hostname)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF' >&2
Usage: proxmox-migration-system-report.sh [--output PATH.md]

  -o, --output PATH   write report here (default: ./proxmox-migration-report-HOSTNAME-YYYYMMDD-HHMMSS.md)
  -h, --help          show this help

All operations are read-only (no writes, no service changes).
EOF
	exit 1
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-o|--output)
			[ "$#" -ge 2 ] || die "--output requires a path"
			OUT="$2"
			shift 2
			;;
		-h|--help) usage ;;
		--) shift; break ;;
		-*) die "unknown option: $1" ;;
		*) die "unexpected argument: $1" ;;
	esac
done

if [ -z "$OUT" ]; then
	OUT="$(pwd)/proxmox-migration-report-${HOST}-$(date +%Y%m%d-%H%M%S).md"
fi

OUT_DIR="$(dirname -- "$OUT")"
[ -d "$OUT_DIR" ] || die "output directory does not exist: $OUT_DIR"
[ -w "$OUT_DIR" ] || die "output directory not writable: $OUT_DIR"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

md_h1() { printf '\n# %s\n\n' "$*" >>"$OUT"; }
md_h2() { printf '\n## %s\n\n' "$*" >>"$OUT"; }
md_h3() { printf '\n### %s\n\n' "$*" >>"$OUT"; }
md_p() { printf '%s\n\n' "$*" >>"$OUT"; }
md_fence() {
	{
		printf '```\n'
		printf '%s\n' "$1"
		printf '```\n\n'
	} >>"$OUT"
}

run() {
	local title="$1" out="" ec=0
	shift
	md_h3 "$title"
	out="$("$@" 2>&1)" || ec=$?
	if [ "$ec" -eq 0 ]; then
		md_fence "$out"
	else
		md_fence "${out}
(exit ${ec})"
	fi
}

run_bash() {
	local title="$1"
	local cmd="$2"
	md_h3 "$title"
	printf '```bash\n%s\n```\n\n' "$cmd" >>"$OUT"
	printf '```\n' >>"$OUT"
	# shellcheck disable=SC2086
	eval "$cmd" >>"$OUT" 2>&1 || printf '(command failed, exit %s)\n' "$?" >>"$OUT"
	printf '```\n\n' >>"$OUT"
}

file_block() {
	local title="$1"
	local path="$2"
	md_h3 "$title"
	if [ -r "$path" ]; then
		printf 'Path: `%s`\n\n' "$path" >>"$OUT"
		printf '```\n' >>"$OUT"
		cat "$path" 2>/dev/null >>"$OUT" || printf '(read failed)\n' >>"$OUT"
		printf '```\n\n' >>"$OUT"
	else
		md_p "Path not present or not readable: \`$path\`"
	fi
}

# ---------------------------------------------------------------------------
# report body
# ---------------------------------------------------------------------------

: >"$OUT"

cat >>"$OUT" <<EOF
# Proxmox migration system report

- **Host:** \`${HOST}\`
- **Generated (UTC):** \`${TS}\`
- **Generator:** \`proxmox-migration-system-report.sh\`

This report was produced using **read-only** inspection commands only.
Review outputs before any destructive migration steps.

EOF

md_h1 "1. Identity and kernel"

run "hostname" hostname -f
run "uname" uname -a
run "os-release" cat /etc/os-release
run "uptime" uptime
run "cmdline" cat /proc/cmdline

md_h1 "2. Hardware summary"

run "CPU model (lscpu)" lscpu
run "Memory" free -h
run "PCI storage class (short)" bash -c 'lspci 2>/dev/null | grep -iE "storage|sata|nvme|scsi|raid" || true'
run "DMI system (if available)" bash -c 'command -v dmidecode >/dev/null && dmidecode -s system-manufacturer 2>/dev/null; command -v dmidecode >/dev/null && dmidecode -s system-product-name 2>/dev/null; true'

md_h1 "3. Block devices and partitions"

run "lsblk (tree)" lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,UUID,PARTUUID
run "lsblk filesystems" lsblk -f
run "blkid" blkid
run "findmnt (all)" findmnt -A -o TARGET,SOURCE,FSTYPE,OPTIONS
run "proc partitions" cat /proc/partitions

md_h2 "3.1 fstab and crypttab"
file_block "/etc/fstab" /etc/fstab
file_block "/etc/crypttab" /etc/crypttab

md_h1 "4. Boot and EFI (proxmox-boot-tool)"

run "proxmox-boot-tool status" proxmox-boot-tool status
run_bash "proxmox-boot-tool list" "proxmox-boot-tool list 2>/dev/null || true"
run "efibootmgr" bash -c 'command -v efibootmgr >/dev/null && efibootmgr -v || printf "efibootmgr not installed\n"'
run_bash "ESP mount (findmnt /boot/efi)" "findmnt /boot/efi 2>/dev/null || printf '/boot/efi not mounted\n'"
run_bash "ls /boot" "ls -la /boot 2>/dev/null || printf 'no /boot listing\n'"
run_bash "ls /boot/efi/EFI (capped)" "ls -laR /boot/efi/EFI 2>/dev/null | head -n 200 || printf 'no EFI tree\n'"
file_block "/etc/kernel/cmdline" /etc/kernel/cmdline
run "kernel packages (dpkg)" bash -c 'dpkg -l | grep -E "^ii\\s+(pve-kernel|linux-image)" || true'

md_h1 "5. ZFS pools and datasets"

run "zpool list" zpool list
run "zpool status -v" zpool status -v
run "zpool get all (each pool)" bash -c 'for p in $(zpool list -H -o name); do echo "==== $p ===="; zpool get all "$p"; done'
run_bash "zfs list (wide)" "zfs list -o name,type,used,avail,refer,mountpoint,mounted,canmount,encryption,keyformat,keylocation,keystatus,encryptionroot,compression,atime,acltype,xattr,volsize,origin 2>/dev/null || zfs list -o name,type,used,avail,refer,mountpoint,mounted,canmount,encryption,keystatus,encryptionroot 2>/dev/null || zfs list"

run "zfs list -t snapshot (recent, capped)" bash -c 'zfs list -t snapshot -o name,creation,used -S creation 2>/dev/null | head -n 80 || true'

md_h2 "5.1 ZFS properties on key datasets (if present)"
for ds in rpool rpool/ROOT rpool/ROOT/pve-1 rpool/data rpool/data-enc rpool/var-lib-vz; do
	if zfs list -H "$ds" >/dev/null 2>&1; then
		md_h3 "zfs get all $ds"
		{
			printf '```\n'
			{ zfs get -H -o property,value,source all "$ds" || printf '(zfs get failed)\n'; } 2>&1
			printf '```\n\n'
		} >>"$OUT"
	fi
done

run "zpool history (last 40 lines)" bash -c 'zpool history 2>/dev/null | tail -n 40 || true'

md_h1 "6. Proxmox node configuration"

run "pveversion" pveversion -v
run "pvesm status" bash -c 'pvesm status 2>&1 || printf "pvesm failed or unavailable\n"'
file_block "/etc/pve/storage.cfg" /etc/pve/storage.cfg
file_block "/etc/pve/datacenter.cfg" /etc/pve/datacenter.cfg
file_block "/etc/pve/user.cfg" /etc/pve/user.cfg
run "cluster status" bash -c 'pvecm status 2>/dev/null || printf "not a cluster node or pvecm unavailable\n"'

md_h1 "7. systemd boot chain (ZFS-related)"

for u in zfs-import-cache.service zfs-import-scan.service zfs-mount.service zfs-load-key.service zfs-load-all-keys-from-usb.service zfs.target local-fs.target multi-user.target; do
	if systemctl cat "$u" >/dev/null 2>&1; then
		md_h2 "unit: $u"
		{
			printf '**systemctl show**\n\n```\n'
			{ systemctl show "$u" -p FragmentPath,LoadState,ActiveState,UnitFileState,ConditionResult,AssertResult,After,Before,Requires,Wants,RequiresMountsFor || true; } 2>&1
			printf '```\n\n**systemctl cat (first 120 lines)**\n\n```\n'
			{ systemctl cat "$u" 2>/dev/null || true; } | head -n 120
			printf '\n```\n\n'
		} >>"$OUT"
	fi
done

run_bash "systemctl list-dependencies zfs.target" "systemctl list-dependencies zfs.target --no-pager 2>/dev/null | head -n 200"
run_bash "systemctl list-dependencies zfs-mount.service" "systemctl list-dependencies zfs-mount.service --no-pager 2>/dev/null | head -n 120"
run_bash "systemd-analyze critical-chain (multi-user.target)" "systemd-analyze critical-chain multi-user.target --no-pager 2>/dev/null | head -n 80 || true"

md_h1 "8. ZFS / initramfs hooks and dracut (if present)"

run "ls /etc/zfs" bash -c 'ls -la /etc/zfs 2>/dev/null || printf "no /etc/zfs\n"'
file_block "/etc/zfs/zfs-list.cache" /etc/zfs/zfs-list.cache
run "ls initramfs-tools conf" bash -c 'ls -la /etc/initramfs-tools/conf.d 2>/dev/null | head -n 50 || true'
run "ls dracut conf" bash -c 'ls -la /etc/dracut.conf.d 2>/dev/null | head -n 50 || true'

md_h1 "9. Network (basics)"

run_bash "ip -brief" "ip -br a 2>/dev/null || true"
file_block "/etc/network/interfaces" /etc/network/interfaces

md_h1 "10. Disk health (non-intrusive SMART identity)"

run "smartctl --scan" bash -c 'command -v smartctl >/dev/null && smartctl --scan-open 2>/dev/null || printf "smartctl not installed\n"'

md_h1 "11. Recent boot journal (errors, capped)"

run_bash "journalctl this boot (priority err, 200 lines)" "journalctl -b -p err --no-pager -n 200 2>/dev/null || true"

md_h1 "End of report"

printf '\n---\n\nReport written to: `%s`\n' "$OUT" >>"$OUT"

printf 'Wrote: %s\n' "$OUT"
