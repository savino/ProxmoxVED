# ZFS encryption helper scripts

This folder contains helper tooling for loading ZFS encryption keys for LXC
datasets and a systemd service template to run the loader early during boot.

Files
- `zfs-load-lxc-keys.sh` — helper script that locates datasets with the
  `custom.proxmox:passfile` property and runs `zfs load-key` using the
  referenced passphrase file.
- `zfs-load-lxc-keys.service` — systemd unit template; copy into
  `/etc/systemd/system/` and enable.

Quick install (on a Proxmox host)

```bash
sudo cp tools/pve/encryption/zfs-load-lxc-keys.sh /usr/local/sbin/
sudo chmod 700 /usr/local/sbin/zfs-load-lxc-keys.sh
sudo cp tools/pve/encryption/zfs-load-lxc-keys.service /etc/systemd/system/zfs-load-lxc-keys.service
sudo systemctl daemon-reload
sudo systemctl enable --now zfs-load-lxc-keys.service
```

Security notes
- Store passphrase files outside encrypted datasets and restrict permissions:
  `chmod 600 /path/to/passfile` and ownership `root:root`.
- Consider using Clevis/Tang or TPM-based unlocking for stronger security.
