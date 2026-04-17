#!/usr/bin/env bash
set -euo pipefail

# zfs-load-lxc-keys.sh
# Load ZFS keys for datasets that have a passfile property set under the
# configured property namespace. Intended to run early during boot before
# `zfs-mount.service` so encrypted datasets can be mounted automatically.

PROP_NS="${PROP_NS:-custom.proxmox}"
PASSFILE_PROP="${PROP_NS}:passfile"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}

need_cmd zfs

printf 'Running zfs-load-lxc-keys (prop: %s)\n' "$PASSFILE_PROP"

datasets=()
if [ "$#" -gt 0 ]; then
  datasets=("$@")
else
  # collect all ZFS filesystems
  while IFS= read -r line; do
    datasets+=("$line")
  done < <(zfs list -H -o name -t filesystem 2>/dev/null || true)
fi

for ds in "${datasets[@]}"; do
  [ -n "$ds" ] || continue
  pf=$(zfs get -H -o value "$PASSFILE_PROP" "$ds" 2>/dev/null || echo "-")
  if [ -z "$pf" ] || [ "$pf" = "-" ]; then
    continue
  fi

  # support file:// prefix
  case "$pf" in
    file://*) keyfile=${pf#file://} ;;
    *) keyfile="$pf" ;;
  esac

  if [ ! -f "$keyfile" ]; then
    printf 'WARN: key file for %s not found: %s\n' "$ds" "$keyfile" >&2
    continue
  fi

  chmod 600 "$keyfile" || true

  keystatus=$(zfs get -H -o value keystatus "$ds" 2>/dev/null || echo "none")
  if [ "$keystatus" = "available" ]; then
    printf 'Key already available for %s\n' "$ds"
    continue
  fi

  if zfs load-key "$ds" 2>/dev/null; then
    printf 'Loaded key for %s\n' "$ds"
  else
    printf 'ERROR: failed to load key for %s\n' "$ds" >&2
  fi
done

exit 0
