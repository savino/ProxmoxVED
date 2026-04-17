#!/usr/bin/env bash
set -euo pipefail

# lxc-zfs-diagnose.sh
# Usage: ./lxc-zfs-diagnose.sh <CTID> <DATASET>
# Example: ./lxc-zfs-diagnose.sh 107 rpool/data/subvol-107-disk-0-enc

CTID="${1:?missing CTID}"
DATASET="${2:?missing DATASET}"
REPORT="lxc-zfs-diagnose-${CTID}-$(date +%Y%m%d-%H%M%S).md"

exec >"$REPORT" 2>&1

echo "# LXC/ZFS Diagnostic Report"
echo

echo "## System Info"
echo '```'
uname -a
pveversion -v || true
echo '```'
echo

echo "## ZFS Dataset Properties ($DATASET)"
echo '```'
zfs get all "$DATASET" || echo "Dataset not found: $DATASET"
echo '```'
echo

echo "## ZFS Key Status"
echo '```'
zfs get keystatus "$DATASET" || true
echo '```'
echo

echo "## ZFS Mountpoint and Status"
echo '```'
zfs get mountpoint,canmount,mounted "$DATASET" || true
echo '```'
echo
echo "## ZFS key/mount events (journal/syslog/pve tasks)"
echo '```'
# recent journal entries mentioning zfs key/mount activity
journalctl -n 500 --no-pager 2>/dev/null | grep -iE 'zfs load-key|zfs mount|zfs: mount|load-key' || true
echo '```'
echo
echo "## ZFS messages in Proxmox task log (/var/log/pve/tasks/index)"
echo '```'
grep -iE 'zfs load-key|zfs mount|mount failed|cannot mount|keystatus' /var/log/pve/tasks/index 2>/dev/null | tail -n 200 || true
echo '```'
echo
echo "## ZFS-related syslog messages (/var/log/syslog)"
echo '```'
grep -iE 'zfs load-key|zfs mount|mount failed|cannot mount|keystatus' /var/log/syslog 2>/dev/null | tail -n 200 || true
echo '```'
echo
echo "## Proxmox Storage Config (zfspool)"
echo '```'
pvesm status | grep zfs || true
pvesm list local-zfs || true
pvesm config local-zfs || true
echo '```'
echo

echo "## LXC Config ($CTID)"
echo '```'
cat "/etc/pve/lxc/${CTID}.conf" || echo "Config not found"
echo '```'
echo

echo "## pct start (skipped; non-invasive diagnostics)"
echo '```'
echo "Skipped starting the container. Run 'pct start ${CTID}' manually to attempt a start." || true
echo '```'
echo
echo "## LXC Status ($CTID)"
echo '```'
pct status "$CTID" 2>&1 || true
echo '```'
echo

echo "## Recent System Logs (journalctl)"
echo '```'
journalctl -n 200 --no-pager || true
echo '```'
echo

echo "## Recent Proxmox Task Logs (/var/log/pve/tasks/index)"
echo '```'
tail -n 200 /var/log/pve/tasks/index || true
echo '```'
echo
echo "## Recent LXC Logs (/var/log/lxc)"
echo '```'
ls -lh /var/log/lxc || true
for f in /var/log/lxc/*"${CTID}"*; do
  [ -e "$f" ] || continue
  echo "---- $f ----"
  tail -n 50 "$f" || true
done
echo '```'
echo
echo "## Recent Syslog (/var/log/syslog)"
echo '```'
tail -n 200 /var/log/syslog || true
echo '```'
echo

echo "## dmesg (last 100 lines)"
echo '```'
dmesg | tail -n 100 || true
echo '```'
echo

echo "## End of Report"
echo "Report saved as $REPORT"
