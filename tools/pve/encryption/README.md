# ZFS encryption scripts for Proxmox storage

This folder contains two approaches for ZFS encryption on Proxmox:

1. Per-dataset conversion for selected CT datasets.
2. Whole-parent migration for `rpool/data`, with a boot-time unlock service that
   simply runs `zfs load-key -a` after a USB key mount is available.

Files
- `encrypt-lxc-dataset.sh` — converts one CT dataset or all eligible CT datasets
  for a single CT into encrypted children.
- `lxc-zfs-diagnose.sh` — non-invasive diagnostic report generator for CT/ZFS
  mount and key-loading issues.
- `encrypt-rpool-data-parent.sh` — migrates the entire `rpool/data` parent into
  a new encrypted parent `rpool/data-enc`, preserving child names and switching
  `local-zfs` to the new parent.
- `zfs-load-lxc-keys.sh` — legacy helper for per-dataset `custom.proxmox:passfile`
  based unlocks.
- `zfs-load-lxc-keys.service` — service template for the legacy per-dataset helper.
- `zfs-load-all-keys-from-usb.service` — service template for whole-parent
  encryption; waits for `/mnt/_USB_PENDRIVE_KEY` and then runs `zfs load-key -a`.

Whole-parent migration flow

```bash
sudo bash tools/pve/encryption/encrypt-rpool-data-parent.sh /root/zfs-pass/rpool-data.pass
```

The script will:
- verify that `local-zfs` points to `rpool/data`
- find CTs and VMs backed by datasets or zvols under `rpool/data`
- stop only the affected guests
- verify that the pool has enough free space for the duplicated data
- create `rpool/data-enc` as an encrypted parent
- migrate every direct child of `rpool/data`
- switch `local-zfs` to `rpool/data-enc`

Boot-time unlock using a USB key mount

```bash
sudo cp tools/pve/encryption/zfs-load-all-keys-from-usb.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now zfs-load-all-keys-from-usb.service
```

Requirements:
- the USB key must be mounted at `/mnt/_USB_PENDRIVE_KEY`
- the passphrase or key files must already be reachable when `zfs load-key -a` runs
- the generated mount unit must be `mnt-_USB_PENDRIVE_KEY.mount`

Legacy per-dataset unlock helper

```bash
sudo cp tools/pve/encryption/zfs-load-lxc-keys.sh /usr/local/sbin/
sudo chmod 700 /usr/local/sbin/zfs-load-lxc-keys.sh
sudo cp tools/pve/encryption/zfs-load-lxc-keys.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now zfs-load-lxc-keys.service
```

Security notes
- Store passphrase files outside encrypted datasets and restrict permissions:
  `chmod 600 /path/to/passfile` and ownership `root:root`.
- For stronger security, prefer hardware-backed or network-backed unlock methods
  such as TPM or Clevis/Tang.
