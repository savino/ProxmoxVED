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
- `prepare-root-encryption.sh` — online preflight + snapshot preparation for
  encrypting `rpool/ROOT` on systems using `proxmox-boot-tool`.
- `apply-root-encryption-initramfs.sh` — offline/initramfs migration helper for
  `rpool/ROOT` encryption.
- `proxmox-migration-system-report.sh` — read-only inventory report (Markdown)
  for hardware, partitions, boot, ZFS, Proxmox, and systemd (migration planning).

System migration report (read-only)

```bash
sudo bash tools/pve/encryption/proxmox-migration-system-report.sh --output /root/proxmox-migration-report.md
```

Run on the target node before tuning migration scripts; review the Markdown output offline.

Encrypting rpool/ROOT (advanced)

This is a high-risk operation and must be done in two phases:

1) Online preparation:

```bash
sudo bash tools/pve/encryption/prepare-root-encryption.sh /mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt --yes
```

2) Offline apply from initramfs/rescue shell:

```bash
bash tools/pve/encryption/apply-root-encryption-initramfs.sh /mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt --snapshot pre-root-encrypt-YYYYMMDD-HHMMSS --yes
```

Notes:
- Do not run `apply-root-encryption-initramfs.sh` from a normally booted rootfs.
- Keep physical/remote-console access available.
- Verify `proxmox-boot-tool status` after successful reboot.

Whole-parent migration flow

```bash
sudo bash tools/pve/encryption/encrypt-rpool-data-parent.sh /root/zfs-pass/rpool-data.pass
```

The script will:
- verify that `local-zfs` points to `rpool/data`
- find CTs and VMs backed by datasets or zvols under `rpool/data`
- stop only the affected guests
- verify that the pool has enough free space for the duplicated data
- create `rpool/data-enc` as an encrypted parent and ensure its key is loaded
- migrate every direct child of `rpool/data` with `zfs send -R | zfs recv` while forcing encrypted receive properties (`encryption`, `keyformat`, `keylocation`) on destination children
- switch `local-zfs` to `rpool/data-enc`
- mount encrypted datasets under `/rpool/data-enc/...` (not `/rpool/data/...`) so Proxmox/LXC pre-start hooks resolve dataset paths correctly

Dry-run behavior
- `--dry-run` performs preflight validation and now also fails if `rpool/data-enc` already exists (for example after a restore where the encrypted tree was intentionally kept).

Important operational note:
- when `local-zfs` points to `rpool/data-enc`, the parent dataset must remain mountable
  (do not force `mountpoint=none` with `canmount=off`) or Proxmox pre-start hooks can fail

Boot unlock is mandatory
- the migration script now fails fast if no key-loading service is enabled
- one supported service must be enabled before migration:
  - `zfs-load-all-keys-from-usb.service` (recommended when passphrase/key is on USB)
  - `zfs-load-key.service` (system-provided fallback, if available on your node)
- if passphrase file lives under `/mnt/_USB_PENDRIVE_KEY`, `zfs-load-all-keys-from-usb.service` is required

Restore mode behavior

```bash
sudo bash tools/pve/encryption/encrypt-rpool-data-parent.sh --restore --yes
```

The restore path now:
- restores `/etc/pve/storage.cfg` from backup
- unmounts `rpool/data-enc` children and sets their mountpoints to `none`
- restores and mounts the original `rpool/data/subvol-*` datasets (from mount backup, or from saved `custom.proxmox:orig-mount` properties as fallback)
  while checking storage paths.

Useful post-check commands:

```bash
pvesm status
awk '/^zfspool:[[:space:]]*local-zfs$/,/^[a-zA-Z]/{print}' /etc/pve/storage.cfg
zfs get encryption,keystatus,mountpoint,mounted rpool/data-enc
pct list
qm list
```

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

Post-migration and post-reboot verification

```bash
# Encryption must be enabled for migrated and newly created children
zfs get -r encryption,encryptionroot,keystatus rpool/data-enc

# local-zfs must point to encrypted parent
awk '/^zfspool:[[:space:]]*local-zfs$/,/^[a-zA-Z]/{print}' /etc/pve/storage.cfg

# Boot unlock service health
systemctl is-enabled zfs-load-all-keys-from-usb.service
systemctl status zfs-load-all-keys-from-usb.service --no-pager
```

Troubleshooting
- Symptom: CT fail at start with `dataset is busy` / `could not activate storage 'local-zfs'` after enabling the USB load-key unit; `systemctl show zfs-mount.service -p ConditionResult` is `no` and `zfs mount -a` never ran.
  - Cause: an older unit used `After=local-fs.target` together with `Before=zfs-mount.service`, which breaks boot ordering (zfs-mount runs before `local-fs.target`).
  - Fix: reinstall `zfs-load-all-keys-from-usb.service` from this repo (no `After=local-fs.target`), then `daemon-reload` and reboot.
- Symptom: new CT/VM fails after reboot, `keystatus=unavailable` on `rpool/data-enc/*`.
  - Fix: verify key file path exists at boot and enable/start `zfs-load-all-keys-from-usb.service`.
- Symptom: old migrated datasets still show `encryption=off`.
  - Cause: data was migrated with old `zfs send|recv` flow from earlier script versions.
  - Fix: rerun migration with this updated script on clean source/target layout.

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
