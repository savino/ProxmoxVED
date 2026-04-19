# Proxmox migration system report

- **Host:** `pve`
- **Generated (UTC):** `2026-04-19T07:20:39Z`
- **Generator:** `proxmox-migration-system-report.sh`

This report was produced using **read-only** inspection commands only.
Review outputs before any destructive migration steps.

# 1. Identity and kernel

### hostname

```
pve.lan
```

### uname

```
Linux pve 6.17.13-2-pve #1 SMP PREEMPT_DYNAMIC PMX 6.17.13-2 (2026-03-13T08:06Z) x86_64 GNU/Linux
```

### os-release

```
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
VERSION_ID="13"
VERSION="13 (trixie)"
VERSION_CODENAME=trixie
DEBIAN_VERSION_FULL=13.4
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
```

### uptime

```
 09:20:39 up  9:25,  5 users,  load average: 0.15, 0.11, 0.09
```

### cmdline

```
BOOT_IMAGE=/vmlinuz-6.17.13-2-pve root=ZFS=/ROOT/pve-1 ro root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet
```

# 2. Hardware summary

### CPU model (lscpu)

```
Architecture:                            x86_64
CPU op-mode(s):                          32-bit, 64-bit
Address sizes:                           39 bits physical, 48 bits virtual
Byte Order:                              Little Endian
CPU(s):                                  4
On-line CPU(s) list:                     0-3
Vendor ID:                               GenuineIntel
Model name:                              Intel(R) Celeron(R) N5105 @ 2.00GHz
CPU family:                              6
Model:                                   156
Thread(s) per core:                      1
Core(s) per socket:                      4
Socket(s):                               1
Stepping:                                0
CPU(s) scaling MHz:                      97%
CPU max MHz:                             2900.0000
CPU min MHz:                             800.0000
BogoMIPS:                                3993.60
Flags:                                   fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx est tm2 ssse3 sdbg cx16 xtpr pdcm sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave rdrand lahf_lm 3dnowprefetch cpuid_fault epb cat_l2 cdp_l2 ssbd ibrs ibpb stibp ibrs_enhanced tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust smep erms rdt_a rdseed smap clflushopt clwb intel_pt sha_ni xsaveopt xsavec xgetbv1 xsaves split_lock_detect dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req vnmi umip waitpkg gfni rdpid movdiri movdir64b md_clear flush_l1d arch_capabilities
Virtualization:                          VT-x
L1d cache:                               128 KiB (4 instances)
L1i cache:                               128 KiB (4 instances)
L2 cache:                                1.5 MiB (1 instance)
L3 cache:                                4 MiB (1 instance)
NUMA node(s):                            1
NUMA node0 CPU(s):                       0-3
Vulnerability Gather data sampling:      Not affected
Vulnerability Ghostwrite:                Not affected
Vulnerability Indirect target selection: Not affected
Vulnerability Itlb multihit:             Not affected
Vulnerability L1tf:                      Not affected
Vulnerability Mds:                       Not affected
Vulnerability Meltdown:                  Not affected
Vulnerability Mmio stale data:           Mitigation; Clear CPU buffers; SMT disabled
Vulnerability Old microcode:             Not affected
Vulnerability Reg file data sampling:    Mitigation; Clear Register File
Vulnerability Retbleed:                  Not affected
Vulnerability Spec rstack overflow:      Not affected
Vulnerability Spec store bypass:         Mitigation; Speculative Store Bypass disabled via prctl
Vulnerability Spectre v1:                Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:                Mitigation; Enhanced / Automatic IBRS; IBPB conditional; PBRSB-eIBRS Not affected; BHI SW loop, KVM SW loop
Vulnerability Srbds:                     Vulnerable: No microcode
Vulnerability Tsa:                       Not affected
Vulnerability Tsx async abort:           Not affected
Vulnerability Vmscape:                   Not affected
```

### Memory

```
               total        used        free      shared  buff/cache   available
Mem:            15Gi       8.7Gi       4.5Gi       112Mi       2.8Gi       6.7Gi
Swap:          7.7Gi        16Ki       7.7Gi
```

### PCI storage class (short)

```
00:17.0 SATA controller: Intel Corporation Jasper Lake SATA AHCI Controller (rev 01)
03:00.0 Non-Volatile memory controller: Silicon Motion, Inc. SM2263EN/SM2263XT (DRAM-less) NVMe SSD Controllers (rev 03)
```

### DMI system (if available)

```
GX55
GX55
```

# 3. Block devices and partitions

### lsblk (tree)

```
NAME          SIZE TYPE FSTYPE     MOUNTPOINTS            MODEL           UUID                                 PARTUUID
sda           7.5G disk                                   USB Flash Drive                                      
├─sda1        7.4G part exfat      /mnt/_USB_PENDRIVE_KEY                 7382-062A                            c0fab980-01
└─sda2         32M part vfat                                              60D4-BE21                            c0fab980-02
zd0             1M disk                                                                                        
zd16           16G disk                                                                                        
zram0         7.7G disk swap       [SWAP]                                 a4967d99-3fe3-4765-9a37-e04325506347 
nvme0n1     238.5G disk                                   Anucell 256GB                                        
├─nvme0n1p1  1007K part                                                                                        7e6b4a85-bf64-429f-b5a7-3102a6974794
├─nvme0n1p2     1G part vfat                                              1578-E2C7                            075d6272-6996-4cbd-a2c7-f17a32b6a41b
└─nvme0n1p3   237G part zfs_member                                        18362814433892345480                 0e2566cd-9a15-4e84-bca0-62cb8258250f
```

### lsblk filesystems

```
NAME        FSTYPE     FSVER LABEL  UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
sda                                                                                     
├─sda1      exfat      1.0   Ventoy 7382-062A                                 2G    73% /mnt/_USB_PENDRIVE_KEY
└─sda2      vfat       FAT16        60D4-BE21                                           
zd0                                                                                     
zd16                                                                                    
zram0       swap       1            a4967d99-3fe3-4765-9a37-e04325506347                [SWAP]
nvme0n1                                                                                 
├─nvme0n1p1                                                                             
├─nvme0n1p2 vfat       FAT32        1578-E2C7                                           
└─nvme0n1p3 zfs_member 5000  rpool  18362814433892345480                                
```

### blkid

```
/dev/nvme0n1p3: LABEL="rpool" UUID="18362814433892345480" UUID_SUB="17763115913241247250" BLOCK_SIZE="4096" TYPE="zfs_member" PARTUUID="0e2566cd-9a15-4e84-bca0-62cb8258250f"
/dev/nvme0n1p2: UUID="1578-E2C7" BLOCK_SIZE="512" TYPE="vfat" PARTUUID="075d6272-6996-4cbd-a2c7-f17a32b6a41b"
/dev/sda2: SEC_TYPE="msdos" UUID="60D4-BE21" BLOCK_SIZE="512" TYPE="vfat" PARTUUID="c0fab980-02"
/dev/sda1: LABEL="Ventoy" UUID="7382-062A" BLOCK_SIZE="512" TYPE="exfat" PARTUUID="c0fab980-01"
/dev/nvme0n1p1: PARTUUID="7e6b4a85-bf64-429f-b5a7-3102a6974794"
/dev/zram0: UUID="a4967d99-3fe3-4765-9a37-e04325506347" TYPE="swap"
```

### findmnt (all)

```
TARGET                                        SOURCE                           FSTYPE      OPTIONS
/                                             rpool/ROOT/pve-1                 zfs         rw,relatime,xattr,posixacl,casesensitive
├─/sys                                        sysfs                            sysfs       rw,nosuid,nodev,noexec,relatime
│ ├─/sys/kernel/security                      securityfs                       securityfs  rw,nosuid,nodev,noexec,relatime
│ ├─/sys/fs/cgroup                            cgroup2                          cgroup2     rw,nosuid,nodev,noexec,relatime
│ ├─/sys/fs/pstore                            none                             pstore      rw,nosuid,nodev,noexec,relatime
│ ├─/sys/firmware/efi/efivars                 efivarfs                         efivarfs    rw,nosuid,nodev,noexec,relatime
│ ├─/sys/fs/bpf                               bpf                              bpf         rw,nosuid,nodev,noexec,relatime,mode=700
│ ├─/sys/kernel/debug                         debugfs                          debugfs     rw,nosuid,nodev,noexec,relatime
│ ├─/sys/kernel/tracing                       tracefs                          tracefs     rw,nosuid,nodev,noexec,relatime
│ ├─/sys/kernel/config                        configfs                         configfs    rw,nosuid,nodev,noexec,relatime
│ └─/sys/fs/fuse/connections                  fusectl                          fusectl     rw,nosuid,nodev,noexec,relatime
├─/proc                                       proc                             proc        rw,relatime
│ └─/proc/sys/fs/binfmt_misc                  systemd-1                        autofs      rw,relatime,fd=37,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=5803
│   └─/proc/sys/fs/binfmt_misc                binfmt_misc                      binfmt_misc rw,nosuid,nodev,noexec,relatime
├─/dev                                        udev                             devtmpfs    rw,nosuid,relatime,size=8027844k,nr_inodes=2006961,mode=755,inode64
│ ├─/dev/pts                                  devpts                           devpts      rw,nosuid,noexec,relatime,gid=5,mode=600,ptmxmode=000
│ ├─/dev/shm                                  tmpfs                            tmpfs       rw,nosuid,nodev,inode64
│ ├─/dev/hugepages                            hugetlbfs                        hugetlbfs   rw,nosuid,nodev,relatime,pagesize=2M
│ └─/dev/mqueue                               mqueue                           mqueue      rw,nosuid,nodev,noexec,relatime
├─/run                                        tmpfs                            tmpfs       rw,nosuid,nodev,noexec,relatime,size=1615200k,mode=755,inode64
│ ├─/run/lock                                 tmpfs                            tmpfs       rw,nosuid,nodev,noexec,relatime,size=5120k,inode64
│ ├─/run/credentials/systemd-journald.service tmpfs                            tmpfs       ro,nosuid,nodev,noexec,relatime,nosymfollow,size=1024k,nr_inodes=1024,mode=700,inode64,noswap
│ ├─/run/rpc_pipefs                           sunrpc                           rpc_pipefs  rw,relatime
│ ├─/run/credentials/getty@tty1.service       tmpfs                            tmpfs       ro,nosuid,nodev,noexec,relatime,nosymfollow,size=1024k,nr_inodes=1024,mode=700,inode64,noswap
│ └─/run/user/0                               tmpfs                            tmpfs       rw,nosuid,nodev,relatime,size=1615196k,nr_inodes=403799,mode=700,inode64
├─/tmp                                        tmpfs                            tmpfs       rw,nosuid,nodev,size=8075996k,nr_inodes=1048576,inode64
├─/mnt/_USB_PENDRIVE_KEY                      /dev/sda1                        exfat       rw,noatime,fmask=0133,dmask=0022,iocharset=utf8,errors=remount-ro
├─/rpool                                      rpool                            zfs         rw,relatime,xattr,noacl,casesensitive
│ ├─/rpool/ROOT                               rpool/ROOT                       zfs         rw,relatime,xattr,noacl,casesensitive
│ └─/rpool/data-enc                           rpool/data-enc                   zfs         rw,relatime,xattr,noacl,casesensitive
│   ├─/rpool/data-enc/subvol-100-disk-0       rpool/data-enc/subvol-100-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-112-disk-0       rpool/data-enc/subvol-112-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-110-disk-0       rpool/data-enc/subvol-110-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-101-disk-0       rpool/data-enc/subvol-101-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-102-disk-0       rpool/data-enc/subvol-102-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-111-disk-0       rpool/data-enc/subvol-111-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-106-disk-0       rpool/data-enc/subvol-106-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-113-disk-0       rpool/data-enc/subvol-113-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-114-disk-0       rpool/data-enc/subvol-114-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-104-disk-0       rpool/data-enc/subvol-104-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-108-disk-0       rpool/data-enc/subvol-108-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-103-disk-0       rpool/data-enc/subvol-103-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-109-disk-0       rpool/data-enc/subvol-109-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-107-disk-0       rpool/data-enc/subvol-107-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-105-disk-0       rpool/data-enc/subvol-105-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-117-disk-0       rpool/data-enc/subvol-117-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   ├─/rpool/data-enc/subvol-116-disk-0       rpool/data-enc/subvol-116-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
│   └─/rpool/data-enc/subvol-115-disk-0       rpool/data-enc/subvol-115-disk-0 zfs         rw,relatime,xattr,posixacl,casesensitive
├─/var/lib/vz                                 rpool/var-lib-vz                 zfs         rw,relatime,xattr,noacl,casesensitive
├─/var/lib/lxcfs                              lxcfs                            fuse.lxcfs  rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other
├─/etc/pve                                    /dev/fuse                        fuse        rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
└─/mnt/pve/PVE-Backup                         //dns-320l/PVE-Backup            cifs        rw,relatime,vers=2.0,cache=strict,upcall_target=app,username=proxmox,uid=0,noforceuid,gid=0,noforcegid,addr=192.168.10.35,file_mode=0755,dir_mode=0755,soft,nounix,serverino,mapposix,reparse=nfs,nativesocket,symlink=native,rsize=65536,wsize=65536,bsize=1048576,retrans=1,echo_interval=60,actimeo=1,closetimeo=1
```

### proc partitions

```
major minor  #blocks  name

 259        0  250059096 nvme0n1
 259        1       1007 nvme0n1p1
 259        2    1048576 nvme0n1p2
 259        3  248511488 nvme0n1p3
   8        0    7819264 sda
   8        1    7785472 sda1
   8        2      32768 sda2
 230        0       1024 zd0
 230       16   16777216 zd16
 251        0    8075996 zram0
```

## 3.1 fstab and crypttab

### /etc/fstab

Path: `/etc/fstab`

```
# <file system> <mount point> <type> <options> <dump> <pass>
proc /proc proc defaults 0 0
# /dev/sda1 (pendrive ZFS key) montato in /mnt/_USB_PENDRIVE_KEY
UUID=7382-062A  /mnt/_USB_PENDRIVE_KEY  exfat  defaults,auto,noatime,uid=0,gid=0,dmask=0022,fmask=0133,x-systemd.before=zfs-mount.service  0 0
```

### /etc/crypttab

Path not present or not readable: `/etc/crypttab`

# 4. Boot and EFI (proxmox-boot-tool)

### proxmox-boot-tool status

```
Re-executing '/usr/sbin/proxmox-boot-tool' in new private mount namespace..
System currently booted with uefi
1578-E2C7 is configured with: grub (versions: 6.17.13-1-pve, 6.17.13-2-pve)
```

### proxmox-boot-tool list

```bash
proxmox-boot-tool list 2>/dev/null || true
```

```

```

### efibootmgr

```
BootCurrent: 0008
Timeout: 1 seconds
BootOrder: 0008,0000,0009,0007
Boot0000* proxmox	HD(2,GPT,075d6272-6996-4cbd-a2c7-f17a32b6a41b,0x800,0x200000)/File(\EFI\PROXMOX\SHIMX64.EFI)
      dp: 04 01 2a 00 02 00 00 00 00 08 00 00 00 00 00 00 00 00 20 00 00 00 00 00 72 62 5d 07 96 69 bd 4c a2 c7 f1 7a 32 b6 a4 1b 02 02 / 04 04 36 00 5c 00 45 00 46 00 49 00 5c 00 50 00 52 00 4f 00 58 00 4d 00 4f 00 58 00 5c 00 53 00 48 00 49 00 4d 00 58 00 36 00 34 00 2e 00 45 00 46 00 49 00 00 00 / 7f ff 04 00
Boot0007  UEFI: PXE IPv4 Realtek PCIe GBE Family Controller	PciRoot(0x0)/Pci(0x1c,0x2)/Pci(0x0,0x0)/MAC(220112a101e1,0)/IPv4(0.0.0.00.0.0.0,0,0)0000424f
      dp: 02 01 0c 00 d0 41 03 0a 00 00 00 00 / 01 01 06 00 02 1c / 01 01 06 00 00 00 / 03 0b 25 00 22 01 12 a1 01 e1 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 / 03 0c 1b 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 / 7f ff 04 00
    data: 00 00 42 4f
Boot0008* UEFI OS	HD(2,GPT,075d6272-6996-4cbd-a2c7-f17a32b6a41b,0x800,0x200000)/File(\EFI\BOOT\BOOTX64.EFI)0000424f
      dp: 04 01 2a 00 02 00 00 00 00 08 00 00 00 00 00 00 00 00 20 00 00 00 00 00 72 62 5d 07 96 69 bd 4c a2 c7 f1 7a 32 b6 a4 1b 02 02 / 04 04 30 00 5c 00 45 00 46 00 49 00 5c 00 42 00 4f 00 4f 00 54 00 5c 00 42 00 4f 00 4f 00 54 00 58 00 36 00 34 00 2e 00 45 00 46 00 49 00 00 00 / 7f ff 04 00
    data: 00 00 42 4f
Boot0009* UEFI: Lexar USB Flash Drive 8.07, Partition 2	PciRoot(0x0)/Pci(0x14,0x0)/USB(0,0)/HD(2,MBR,0xc0fab980,0xeda000,0x10000)0000424f
      dp: 02 01 0c 00 d0 41 03 0a 00 00 00 00 / 01 01 06 00 00 14 / 03 05 06 00 00 00 / 04 01 2a 00 02 00 00 00 00 a0 ed 00 00 00 00 00 00 00 01 00 00 00 00 00 80 b9 fa c0 00 00 00 00 00 00 00 00 00 00 00 00 01 01 / 7f ff 04 00
    data: 00 00 42 4f
```

### ESP mount (findmnt /boot/efi)

```bash
findmnt /boot/efi 2>/dev/null || printf '/boot/efi not mounted\n'
```

```
/boot/efi not mounted
```

### ls /boot

```bash
ls -la /boot 2>/dev/null || printf 'no /boot listing\n'
```

```
total 519275
drwxr-xr-x  5 root root       29 Mar 31 16:25 .
drwxr-xr-x 18 root root       22 Apr 14 18:35 ..
-rw-r--r--  1 root root   302453 Feb 10 15:06 config-6.17.13-1-pve
-rw-r--r--  1 root root   302305 Mar 13 09:06 config-6.17.13-2-pve
-rw-r--r--  1 root root   302240 Oct 21 13:55 config-6.17.2-1-pve
-rw-r--r--  1 root root   302297 Dec 19 08:49 config-6.17.4-2-pve
-rw-r--r--  1 root root   302445 Jan 12 17:25 config-6.17.9-1-pve
drwxr-xr-x  2 root root        2 Feb  3 17:24 efi
drwxr-xr-x  2 root root        5 Mar 31 16:25 grub
-rw-r--r--  1 root root 88829172 Feb 28 23:05 initrd.img-6.17.13-1-pve
-rw-r--r--  1 root root 88850114 Mar 31 16:25 initrd.img-6.17.13-2-pve
-rw-r--r--  1 root root 86228722 Feb  3 17:27 initrd.img-6.17.2-1-pve
-rw-r--r--  1 root root 87908870 Feb  3 17:51 initrd.img-6.17.4-2-pve
-rw-r--r--  1 root root 87931644 Feb  6 12:19 initrd.img-6.17.9-1-pve
-rw-r--r--  1 root root   151020 Nov 17  2024 memtest86+ia32.bin
-rw-r--r--  1 root root   152064 Nov 17  2024 memtest86+ia32.efi
-rw-r--r--  1 root root   155992 Nov 17  2024 memtest86+x64.bin
-rw-r--r--  1 root root   157184 Nov 17  2024 memtest86+x64.efi
drwxr-xr-x  2 root root        6 Mar 31 16:25 pve
-rw-r--r--  1 root root  9132428 Feb 10 15:06 System.map-6.17.13-1-pve
-rw-r--r--  1 root root  9132579 Mar 13 09:06 System.map-6.17.13-2-pve
-rw-r--r--  1 root root  9125340 Oct 21 13:55 System.map-6.17.2-1-pve
-rw-r--r--  1 root root  9129081 Dec 19 08:49 System.map-6.17.4-2-pve
-rw-r--r--  1 root root  9131658 Jan 12 17:25 System.map-6.17.9-1-pve
-rw-r--r--  1 root root 15842088 Feb 10 15:06 vmlinuz-6.17.13-1-pve
-rw-r--r--  1 root root 15837992 Mar 13 09:06 vmlinuz-6.17.13-2-pve
-rw-r--r--  1 root root 15367272 Oct 21 13:55 vmlinuz-6.17.2-1-pve
-rw-r--r--  1 root root 15817512 Dec 19 08:49 vmlinuz-6.17.4-2-pve
-rw-r--r--  1 root root 15821608 Jan 12 17:25 vmlinuz-6.17.9-1-pve
```

### ls /boot/efi/EFI (capped)

```bash
ls -laR /boot/efi/EFI 2>/dev/null | head -n 200 || printf 'no EFI tree\n'
```

```
no EFI tree
```

### /etc/kernel/cmdline

Path: `/etc/kernel/cmdline`

```
root=ZFS=rpool/ROOT/pve-1 boot=zfs 
```

### kernel packages (dpkg)

```

```

# 5. ZFS pools and datasets

### zpool list

```
NAME    SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
rpool   236G  74.9G   161G        -         -    27%    31%  1.00x    ONLINE  -
```

### zpool status -v

```
  pool: rpool
 state: ONLINE
status: Some supported and requested features are not enabled on the pool.
	The pool can still be used, but some features are unavailable.
action: Enable all features using 'zpool upgrade'. Once this is done,
	the pool may no longer be accessible by software that does not support
	the features. See zpool-features(7) for details.
  scan: scrub repaired 0B in 00:00:54 with 0 errors on Sun Apr 12 00:24:56 2026
config:

	NAME                                             STATE     READ WRITE CKSUM
	rpool                                            ONLINE       0     0     0
	  nvme-Anucell_256GB_AA000000000000001480-part3  ONLINE       0     0     0

errors: No known data errors
```

### zpool get all (each pool)

```
==== rpool ====
NAME   PROPERTY                       VALUE                          SOURCE
rpool  size                           236G                           -
rpool  capacity                       31%                            -
rpool  altroot                        -                              default
rpool  health                         ONLINE                         -
rpool  guid                           18362814433892345480           -
rpool  version                        -                              default
rpool  bootfs                         rpool/ROOT/pve-1               local
rpool  delegation                     on                             default
rpool  autoreplace                    off                            default
rpool  cachefile                      -                              default
rpool  failmode                       wait                           default
rpool  listsnapshots                  off                            default
rpool  autoexpand                     off                            default
rpool  dedupratio                     1.00x                          -
rpool  free                           161G                           -
rpool  allocated                      74.9G                          -
rpool  readonly                       off                            -
rpool  ashift                         12                             local
rpool  comment                        -                              default
rpool  expandsize                     -                              -
rpool  freeing                        0                              -
rpool  fragmentation                  27%                            -
rpool  leaked                         0                              -
rpool  multihost                      off                            default
rpool  checkpoint                     -                              -
rpool  load_guid                      10022816801139721079           -
rpool  autotrim                       off                            default
rpool  compatibility                  off                            default
rpool  bcloneused                     513M                           -
rpool  bclonesaved                    549M                           -
rpool  bcloneratio                    2.07x                          -
rpool  dedup_table_size               0                              -
rpool  dedup_table_quota              auto                           default
rpool  last_scrubbed_txg              1137291                        -
rpool  feature@async_destroy          enabled                        local
rpool  feature@empty_bpobj            active                         local
rpool  feature@lz4_compress           active                         local
rpool  feature@multi_vdev_crash_dump  enabled                        local
rpool  feature@spacemap_histogram     active                         local
rpool  feature@enabled_txg            active                         local
rpool  feature@hole_birth             active                         local
rpool  feature@extensible_dataset     active                         local
rpool  feature@embedded_data          active                         local
rpool  feature@bookmarks              enabled                        local
rpool  feature@filesystem_limits      enabled                        local
rpool  feature@large_blocks           enabled                        local
rpool  feature@large_dnode            enabled                        local
rpool  feature@sha512                 enabled                        local
rpool  feature@skein                  enabled                        local
rpool  feature@edonr                  enabled                        local
rpool  feature@userobj_accounting     active                         local
rpool  feature@encryption             active                         local
rpool  feature@project_quota          active                         local
rpool  feature@device_removal         enabled                        local
rpool  feature@obsolete_counts        enabled                        local
rpool  feature@zpool_checkpoint       enabled                        local
rpool  feature@spacemap_v2            active                         local
rpool  feature@allocation_classes     enabled                        local
rpool  feature@resilver_defer         enabled                        local
rpool  feature@bookmark_v2            enabled                        local
rpool  feature@redaction_bookmarks    enabled                        local
rpool  feature@redacted_datasets      enabled                        local
rpool  feature@bookmark_written       enabled                        local
rpool  feature@log_spacemap           active                         local
rpool  feature@livelist               enabled                        local
rpool  feature@device_rebuild         enabled                        local
rpool  feature@zstd_compress          enabled                        local
rpool  feature@draid                  enabled                        local
rpool  feature@zilsaxattr             active                         local
rpool  feature@head_errlog            active                         local
rpool  feature@blake3                 enabled                        local
rpool  feature@block_cloning          active                         local
rpool  feature@vdev_zaps_v2           active                         local
rpool  feature@redaction_list_spill   enabled                        local
rpool  feature@raidz_expansion        enabled                        local
rpool  feature@fast_dedup             enabled                        local
rpool  feature@longname               enabled                        local
rpool  feature@large_microzap         enabled                        local
rpool  feature@dynamic_gang_header    disabled                       local
rpool  feature@block_cloning_endian   disabled                       local
rpool  feature@physical_rewrite       disabled                       local
```

### zfs list (wide)

```bash
zfs list -o name,type,used,avail,refer,mountpoint,mounted,canmount,encryption,keyformat,keylocation,keystatus,encryptionroot,compression,atime,acltype,xattr,volsize,origin 2>/dev/null || zfs list -o name,type,used,avail,refer,mountpoint,mounted,canmount,encryption,keystatus,encryptionroot 2>/dev/null || zfs list
```

```
NAME                              TYPE         USED  AVAIL  REFER  MOUNTPOINT                         MOUNTED  CANMOUNT  ENCRYPTION   KEYFORMAT   KEYLOCATION                                            KEYSTATUS    ENCROOT                           COMPRESS        ATIME  ACLTYPE   XATTR  VOLSIZE  ORIGIN
rpool                             filesystem  75.4G   154G   136K  /rpool                             yes      on        off          none        none                                                   -            -                                 on              on     off       sa           -  -
rpool/ROOT                        filesystem  5.31G   154G    96K  /rpool/ROOT                        yes      on        off          none        none                                                   -            -                                 on              on     off       sa           -  -
rpool/ROOT/pve-1                  filesystem  5.31G   154G  5.31G  /                                  yes      on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data                        filesystem  31.2G   154G   128K  none                               no       on        off          none        none                                                   -            -                                 on              on     off       sa           -  -
rpool/data-enc                    filesystem  36.5G   154G   432K  /rpool/data-enc                    yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc                    on              on     off       sa           -  -
rpool/data-enc/subvol-100-disk-0  filesystem   751M  9.37G   650M  /rpool/data-enc/subvol-100-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-100-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-101-disk-0  filesystem  1.12G  6.94G  1.06G  /rpool/data-enc/subvol-101-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-101-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-102-disk-0  filesystem  1.87G  6.30G  1.70G  /rpool/data-enc/subvol-102-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-102-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-103-disk-0  filesystem  72.3M   955M  68.7M  /rpool/data-enc/subvol-103-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-103-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-104-disk-0  filesystem  99.4M   929M  95.0M  /rpool/data-enc/subvol-104-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-104-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-105-disk-0  filesystem   569M  1.49G   525M  /rpool/data-enc/subvol-105-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-105-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-106-disk-0  filesystem   857M  7.16G   857M  /rpool/data-enc/subvol-106-disk-0  yes      on        aes-256-gcm  passphrase  none                                                   available    rpool/data-enc                    on              on     posix     sa           -  -
rpool/data-enc/subvol-107-disk-0  filesystem   966M  3.14G   882M  /rpool/data-enc/subvol-107-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-107-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-108-disk-0  filesystem   550M  2.50G   511M  /rpool/data-enc/subvol-108-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-108-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-109-disk-0  filesystem  1.46G  1.87G  1.13G  /rpool/data-enc/subvol-109-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-109-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-110-disk-0  filesystem  3.86G  16.3G  3.68G  /rpool/data-enc/subvol-110-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-110-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-111-disk-0  filesystem  7.18G  43.0G  6.98G  /rpool/data-enc/subvol-111-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-111-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-112-disk-0  filesystem  2.68G  13.5G  2.48G  /rpool/data-enc/subvol-112-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-112-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-113-disk-0  filesystem   587M  3.46G   548M  /rpool/data-enc/subvol-113-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-113-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-114-disk-0  filesystem  3.04G  5.15G  2.85G  /rpool/data-enc/subvol-114-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-114-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-115-disk-0  filesystem  6.78G  13.6G  6.42G  /rpool/data-enc/subvol-115-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-115-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-116-disk-0  filesystem  3.24G  6.99G  3.01G  /rpool/data-enc/subvol-116-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-116-disk-0  on              on     posix     sa           -  -
rpool/data-enc/subvol-117-disk-0  filesystem   991M  3.20G   821M  /rpool/data-enc/subvol-117-disk-0  yes      on        aes-256-gcm  passphrase  file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt  available    rpool/data-enc/subvol-117-disk-0  on              on     posix     sa           -  -
rpool/data-enc/vm-118-disk-0      volume       228K   154G   228K  -                                  -        -         aes-256-gcm  passphrase  none                                                   available    rpool/data-enc                    on              -      -         -           1M  -
rpool/data-enc/vm-118-disk-1      volume        88K   154G    88K  -                                  -        -         aes-256-gcm  passphrase  none                                                   available    rpool/data-enc                    on              -      -         -          16G  -
rpool/data/subvol-100-disk-0      filesystem   597M  9.42G   594M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-101-disk-0      filesystem  1021M  7.01G  1016M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-102-disk-0      filesystem  1.61G  6.40G  1.60G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-103-disk-0      filesystem  66.6M   958M  66.2M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-104-disk-0      filesystem  92.6M   932M  92.0M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-105-disk-0      filesystem   492M  1.52G   487M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-107-disk-0      filesystem   822M  3.21G   811M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-108-disk-0      filesystem   476M  2.54G   474M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-109-disk-0      filesystem  1.02G  2.02G   999M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-110-disk-0      filesystem  3.54G  16.5G  3.52G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-111-disk-0      filesystem  6.79G  43.2G  6.77G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-112-disk-0      filesystem  2.20G  13.8G  2.20G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-113-disk-0      filesystem   513M  3.50G   511M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-114-disk-0      filesystem  2.62G  5.39G  2.61G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-115-disk-0      filesystem  5.96G  14.1G  5.95G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-116-disk-0      filesystem  2.70G  7.31G  2.69G  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/data/subvol-117-disk-0      filesystem   801M  3.27G   743M  none                               no       on        off          none        none                                                   -            -                                 on              on     posix     sa           -  -
rpool/var-lib-vz                  filesystem  2.25G   154G  2.25G  /var/lib/vz                        yes      on        off          none        none                                                   -            -                                 on              on     off       sa           -  -
```

### zfs list -t snapshot (recent, capped)

```
NAME                                                                 CREATION                USED
rpool/data@pre-parent-encrypt-20260418-232801                        Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-100-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-101-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-102-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-103-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-104-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-105-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-107-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-108-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-109-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-110-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-111-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-112-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-113-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-114-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-115-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-116-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data-enc/subvol-117-disk-0@pre-parent-encrypt-20260418-232801  Sat Apr 18 23:28 2026     0B
rpool/data/subvol-100-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-101-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-102-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-103-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-104-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-105-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-107-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-108-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-109-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-110-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-111-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-112-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-113-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-114-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-115-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-116-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data/subvol-117-disk-0@pre-parent-encrypt-20260418-232801      Sat Apr 18 23:28 2026     8K
rpool/data@pre-parent-encrypt-20260418-231251                        Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-100-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-101-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-102-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-103-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-104-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-105-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-107-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-108-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-109-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-110-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-111-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-112-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-113-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-114-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-115-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-116-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data-enc/subvol-117-disk-0@pre-parent-encrypt-20260418-231251  Sat Apr 18 23:24 2026     0B
rpool/data/subvol-100-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-101-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-102-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-103-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-104-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-105-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-107-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-108-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-109-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-110-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-111-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-112-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-113-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-114-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-115-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-116-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data/subvol-117-disk-0@pre-parent-encrypt-20260418-231251      Sat Apr 18 23:24 2026     8K
rpool/data@pre-parent-encrypt-20260418-104854                        Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-100-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-101-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-102-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-103-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-104-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-105-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
rpool/data-enc/subvol-107-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026  1.62M
rpool/data-enc/subvol-108-disk-0@pre-parent-encrypt-20260418-104854  Sat Apr 18 10:49 2026     0B
```

## 5.1 ZFS properties on key datasets (if present)

### zfs get all rpool

```
type	filesystem	-
creation	Tue Feb  3 17:24 2026	-
used	75.4G	-
available	154G	-
referenced	136K	-
compressratio	1.74x	-
mounted	yes	-
quota	none	default
reservation	none	default
recordsize	128K	default
mountpoint	/rpool	default
sharenfs	off	default
checksum	on	default
compression	on	local
atime	on	local
devices	on	default
exec	on	default
setuid	on	default
readonly	off	default
zoned	off	default
snapdir	hidden	default
aclmode	discard	default
aclinherit	restricted	default
createtxg	1	-
canmount	on	default
xattr	sa	default
copies	1	default
version	5	-
utf8only	off	-
normalization	none	-
casesensitivity	sensitive	-
vscan	off	default
nbmand	off	default
sharesmb	off	default
refquota	none	default
refreservation	none	default
guid	6606893496872329507	-
primarycache	all	default
secondarycache	all	default
usedbysnapshots	0B	-
usedbydataset	136K	-
usedbychildren	75.4G	-
usedbyrefreservation	0B	-
logbias	latency	default
objsetid	54	-
dedup	off	default
mlslabel	none	default
sync	standard	local
dnodesize	legacy	default
refcompressratio	1.00x	-
written	136K	-
logicalused	117G	-
logicalreferenced	57K	-
volmode	default	default
filesystem_limit	none	default
snapshot_limit	none	default
filesystem_count	none	default
snapshot_count	none	default
snapdev	hidden	default
acltype	off	default
context	none	default
fscontext	none	default
defcontext	none	default
rootcontext	none	default
relatime	on	local
redundant_metadata	all	default
overlay	on	default
encryption	off	default
keylocation	none	default
keyformat	none	default
pbkdf2iters	0	default
special_small_blocks	0	default
prefetch	all	default
direct	standard	default
longname	off	default
defaultuserquota	0	-
defaultgroupquota	0	-
defaultprojectquota	0	-
defaultuserobjquota	0	-
defaultgroupobjquota	0	-
defaultprojectobjquota	0	-
```

### zfs get all rpool/ROOT

```
type	filesystem	-
creation	Tue Feb  3 17:24 2026	-
used	5.31G	-
available	154G	-
referenced	96K	-
compressratio	1.76x	-
mounted	yes	-
quota	none	default
reservation	none	default
recordsize	128K	default
mountpoint	/rpool/ROOT	default
sharenfs	off	default
checksum	on	default
compression	on	inherited from rpool
atime	on	inherited from rpool
devices	on	default
exec	on	default
setuid	on	default
readonly	off	default
zoned	off	default
snapdir	hidden	default
aclmode	discard	default
aclinherit	restricted	default
createtxg	8	-
canmount	on	default
xattr	sa	default
copies	1	default
version	5	-
utf8only	off	-
normalization	none	-
casesensitivity	sensitive	-
vscan	off	default
nbmand	off	default
sharesmb	off	default
refquota	none	default
refreservation	none	default
guid	4774592098307402935	-
primarycache	all	default
secondarycache	all	default
usedbysnapshots	0B	-
usedbydataset	96K	-
usedbychildren	5.31G	-
usedbyrefreservation	0B	-
logbias	latency	default
objsetid	387	-
dedup	off	default
mlslabel	none	default
sync	standard	inherited from rpool
dnodesize	legacy	default
refcompressratio	1.00x	-
written	96K	-
logicalused	9.15G	-
logicalreferenced	42K	-
volmode	default	default
filesystem_limit	none	default
snapshot_limit	none	default
filesystem_count	none	default
snapshot_count	none	default
snapdev	hidden	default
acltype	off	default
context	none	default
fscontext	none	default
defcontext	none	default
rootcontext	none	default
relatime	on	inherited from rpool
redundant_metadata	all	default
overlay	on	default
encryption	off	default
keylocation	none	default
keyformat	none	default
pbkdf2iters	0	default
special_small_blocks	0	default
prefetch	all	default
direct	standard	default
longname	off	default
defaultuserquota	0	-
defaultgroupquota	0	-
defaultprojectquota	0	-
defaultuserobjquota	0	-
defaultgroupobjquota	0	-
defaultprojectobjquota	0	-
```

### zfs get all rpool/ROOT/pve-1

```
type	filesystem	-
creation	Tue Feb  3 17:24 2026	-
used	5.31G	-
available	154G	-
referenced	5.31G	-
compressratio	1.76x	-
mounted	yes	-
quota	none	default
reservation	none	default
recordsize	128K	default
mountpoint	/	local
sharenfs	off	default
checksum	on	default
compression	on	inherited from rpool
atime	on	inherited from rpool
devices	on	default
exec	on	default
setuid	on	default
readonly	off	default
zoned	off	default
snapdir	hidden	default
aclmode	discard	default
aclinherit	restricted	default
createtxg	9	-
canmount	on	default
xattr	sa	default
copies	1	default
version	5	-
utf8only	off	-
normalization	none	-
casesensitivity	sensitive	-
vscan	off	default
nbmand	off	default
sharesmb	off	default
refquota	none	default
refreservation	none	default
guid	8251587521957486490	-
primarycache	all	default
secondarycache	all	default
usedbysnapshots	0B	-
usedbydataset	5.31G	-
usedbychildren	0B	-
usedbyrefreservation	0B	-
logbias	latency	default
objsetid	260	-
dedup	off	default
mlslabel	none	default
sync	standard	inherited from rpool
dnodesize	legacy	default
refcompressratio	1.76x	-
written	5.31G	-
logicalused	9.15G	-
logicalreferenced	9.15G	-
volmode	default	default
filesystem_limit	none	default
snapshot_limit	none	default
filesystem_count	none	default
snapshot_count	none	default
snapdev	hidden	default
acltype	posix	local
context	none	default
fscontext	none	default
defcontext	none	default
rootcontext	none	default
relatime	on	inherited from rpool
redundant_metadata	all	default
overlay	on	default
encryption	off	default
keylocation	none	default
keyformat	none	default
pbkdf2iters	0	default
special_small_blocks	0	default
prefetch	all	default
direct	standard	default
longname	off	default
defaultuserquota	0	-
defaultgroupquota	0	-
defaultprojectquota	0	-
defaultuserobjquota	0	-
defaultgroupobjquota	0	-
defaultprojectobjquota	0	-
```

### zfs get all rpool/data

```
type	filesystem	-
creation	Tue Feb  3 17:24 2026	-
used	31.2G	-
available	154G	-
referenced	128K	-
compressratio	1.78x	-
mounted	no	-
quota	none	default
reservation	none	default
recordsize	128K	default
mountpoint	none	local
sharenfs	off	default
checksum	on	default
compression	on	inherited from rpool
atime	on	inherited from rpool
devices	on	default
exec	on	default
setuid	on	default
readonly	off	default
zoned	off	default
snapdir	hidden	default
aclmode	discard	default
aclinherit	restricted	default
createtxg	10	-
canmount	on	default
xattr	sa	default
copies	1	default
version	5	-
utf8only	off	-
normalization	none	-
casesensitivity	sensitive	-
vscan	off	default
nbmand	off	default
sharesmb	off	default
refquota	none	default
refreservation	none	default
guid	2064195204741424190	-
primarycache	all	default
secondarycache	all	default
usedbysnapshots	96K	-
usedbydataset	128K	-
usedbychildren	31.2G	-
usedbyrefreservation	0B	-
logbias	latency	default
objsetid	267	-
dedup	off	default
mlslabel	none	default
sync	standard	inherited from rpool
dnodesize	legacy	default
refcompressratio	1.00x	-
written	0	-
logicalused	50.9G	-
logicalreferenced	55.5K	-
volmode	default	default
filesystem_limit	none	default
snapshot_limit	none	default
filesystem_count	none	default
snapshot_count	none	default
snapdev	hidden	default
acltype	off	default
context	none	default
fscontext	none	default
defcontext	none	default
rootcontext	none	default
relatime	on	inherited from rpool
redundant_metadata	all	default
overlay	on	default
encryption	off	default
keylocation	none	default
keyformat	none	default
pbkdf2iters	0	default
special_small_blocks	0	default
snapshots_changed	Sat Apr 18 23:28:20 2026	-
prefetch	all	default
direct	standard	default
longname	off	default
defaultuserquota	0	-
defaultgroupquota	0	-
defaultprojectquota	0	-
defaultuserobjquota	0	-
defaultgroupobjquota	0	-
defaultprojectobjquota	0	-
```

### zfs get all rpool/data-enc

```
type	filesystem	-
creation	Sat Apr 18 23:28 2026	-
used	36.5G	-
available	154G	-
referenced	432K	-
compressratio	1.75x	-
mounted	yes	-
quota	none	default
reservation	none	default
recordsize	128K	default
mountpoint	/rpool/data-enc	local
sharenfs	off	default
checksum	on	default
compression	on	inherited from rpool
atime	on	inherited from rpool
devices	on	default
exec	on	default
setuid	on	default
readonly	off	default
zoned	off	default
snapdir	hidden	default
aclmode	discard	default
aclinherit	restricted	default
createtxg	1233324	-
canmount	on	default
xattr	sa	default
copies	1	default
version	5	-
utf8only	off	-
normalization	none	-
casesensitivity	sensitive	-
vscan	off	default
nbmand	off	default
sharesmb	off	default
refquota	none	default
refreservation	none	default
guid	7562442393807827057	-
primarycache	all	default
secondarycache	all	default
usedbysnapshots	0B	-
usedbydataset	432K	-
usedbychildren	36.5G	-
usedbyrefreservation	0B	-
logbias	latency	default
objsetid	585	-
dedup	off	default
mlslabel	none	default
sync	standard	inherited from rpool
dnodesize	legacy	default
refcompressratio	1.00x	-
written	432K	-
logicalused	54.6G	-
logicalreferenced	128K	-
volmode	default	default
filesystem_limit	none	default
snapshot_limit	none	default
filesystem_count	none	default
snapshot_count	none	default
snapdev	hidden	default
acltype	off	default
context	none	default
fscontext	none	default
defcontext	none	default
rootcontext	none	default
relatime	on	inherited from rpool
redundant_metadata	all	default
overlay	on	default
encryption	aes-256-gcm	-
keylocation	file:///mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt	local
keyformat	passphrase	-
pbkdf2iters	350000	-
encryptionroot	rpool/data-enc	-
keystatus	available	-
special_small_blocks	0	default
prefetch	all	default
direct	standard	default
longname	off	default
defaultuserquota	0	-
defaultgroupquota	0	-
defaultprojectquota	0	-
defaultuserobjquota	0	-
defaultgroupobjquota	0	-
defaultprojectobjquota	0	-
custom.proxmox:passfile	/mnt/_USB_PENDRIVE_KEY/proxmox-system-init.txt	local
custom.proxmox:source-parent	rpool/data	local
custom.proxmox:note	whole-parent-migration	local
custom.proxmox:passfile-size	33	local
custom.proxmox:passfile-sha256	98f26c90cbe907d7bb52757cd3f867744b96a84f3f897b917a770146b644053c	local
```

### zfs get all rpool/var-lib-vz

```
type	filesystem	-
creation	Tue Feb  3 17:24 2026	-
used	2.25G	-
available	154G	-
referenced	2.25G	-
compressratio	1.00x	-
mounted	yes	-
quota	none	default
reservation	none	default
recordsize	128K	default
mountpoint	/var/lib/vz	local
sharenfs	off	default
checksum	on	default
compression	on	inherited from rpool
atime	on	inherited from rpool
devices	on	default
exec	on	default
setuid	on	default
readonly	off	default
zoned	off	default
snapdir	hidden	default
aclmode	discard	default
aclinherit	restricted	default
createtxg	11	-
canmount	on	default
xattr	sa	default
copies	1	default
version	5	-
utf8only	off	-
normalization	none	-
casesensitivity	sensitive	-
vscan	off	default
nbmand	off	default
sharesmb	off	default
refquota	none	default
refreservation	none	default
guid	16564619194922836489	-
primarycache	all	default
secondarycache	all	default
usedbysnapshots	0B	-
usedbydataset	2.25G	-
usedbychildren	0B	-
usedbyrefreservation	0B	-
logbias	latency	default
objsetid	274	-
dedup	off	default
mlslabel	none	default
sync	standard	inherited from rpool
dnodesize	legacy	default
refcompressratio	1.00x	-
written	2.25G	-
logicalused	2.26G	-
logicalreferenced	2.26G	-
volmode	default	default
filesystem_limit	none	default
snapshot_limit	none	default
filesystem_count	none	default
snapshot_count	none	default
snapdev	hidden	default
acltype	off	default
context	none	default
fscontext	none	default
defcontext	none	default
rootcontext	none	default
relatime	on	inherited from rpool
redundant_metadata	all	default
overlay	on	default
encryption	off	default
keylocation	none	default
keyformat	none	default
pbkdf2iters	0	default
special_small_blocks	0	default
prefetch	all	default
direct	standard	default
longname	off	default
defaultuserquota	0	-
defaultgroupquota	0	-
defaultprojectquota	0	-
defaultuserobjquota	0	-
defaultgroupobjquota	0	-
defaultprojectobjquota	0	-
```

### zpool history (last 40 lines)

```
2026-04-19.01:04:56 zfs snapshot rpool/data-enc/subvol-105-disk-0@vzdump
2026-04-19.01:04:56 zfs set pve-storage:refquota=2147483648 rpool/data-enc/subvol-105-disk-0@vzdump
2026-04-19.01:05:46 zfs destroy rpool/data-enc/subvol-105-disk-0@vzdump
2026-04-19.01:05:47 zfs snapshot rpool/data-enc/subvol-106-disk-0@vzdump
2026-04-19.01:05:47 zfs set pve-storage:refquota=8589934592 rpool/data-enc/subvol-106-disk-0@vzdump
2026-04-19.01:07:02 zfs destroy rpool/data-enc/subvol-106-disk-0@vzdump
2026-04-19.01:07:02 zfs snapshot rpool/data-enc/subvol-107-disk-0@vzdump
2026-04-19.01:07:03 zfs set pve-storage:refquota=4294967296 rpool/data-enc/subvol-107-disk-0@vzdump
2026-04-19.01:08:22 zfs destroy rpool/data-enc/subvol-107-disk-0@vzdump
2026-04-19.01:08:23 zfs snapshot rpool/data-enc/subvol-108-disk-0@vzdump
2026-04-19.01:08:23 zfs set pve-storage:refquota=3221225472 rpool/data-enc/subvol-108-disk-0@vzdump
2026-04-19.01:09:12 zfs destroy rpool/data-enc/subvol-108-disk-0@vzdump
2026-04-19.01:09:12 zfs snapshot rpool/data-enc/subvol-109-disk-0@vzdump
2026-04-19.01:09:12 zfs set pve-storage:refquota=3221225472 rpool/data-enc/subvol-109-disk-0@vzdump
2026-04-19.01:10:42 zfs destroy rpool/data-enc/subvol-109-disk-0@vzdump
2026-04-19.01:10:42 zfs snapshot rpool/data-enc/subvol-110-disk-0@vzdump
2026-04-19.01:10:42 zfs set pve-storage:refquota=21474836480 rpool/data-enc/subvol-110-disk-0@vzdump
2026-04-19.01:15:40 zfs destroy rpool/data-enc/subvol-110-disk-0@vzdump
2026-04-19.01:15:40 zfs snapshot rpool/data-enc/subvol-111-disk-0@vzdump
2026-04-19.01:15:40 zfs set pve-storage:refquota=53687091200 rpool/data-enc/subvol-111-disk-0@vzdump
2026-04-19.01:25:25 zfs destroy rpool/data-enc/subvol-111-disk-0@vzdump
2026-04-19.01:25:25 zfs snapshot rpool/data-enc/subvol-112-disk-0@vzdump
2026-04-19.01:25:25 zfs set pve-storage:refquota=17179869184 rpool/data-enc/subvol-112-disk-0@vzdump
2026-04-19.01:27:59 zfs destroy rpool/data-enc/subvol-112-disk-0@vzdump
2026-04-19.01:27:59 zfs snapshot rpool/data-enc/subvol-113-disk-0@vzdump
2026-04-19.01:27:59 zfs set pve-storage:refquota=4294967296 rpool/data-enc/subvol-113-disk-0@vzdump
2026-04-19.01:28:51 zfs destroy rpool/data-enc/subvol-113-disk-0@vzdump
2026-04-19.01:28:51 zfs snapshot rpool/data-enc/subvol-114-disk-0@vzdump
2026-04-19.01:28:51 zfs set pve-storage:refquota=8589934592 rpool/data-enc/subvol-114-disk-0@vzdump
2026-04-19.01:32:10 zfs destroy rpool/data-enc/subvol-114-disk-0@vzdump
2026-04-19.01:32:10 zfs snapshot rpool/data-enc/subvol-115-disk-0@vzdump
2026-04-19.01:32:10 zfs set pve-storage:refquota=21474836480 rpool/data-enc/subvol-115-disk-0@vzdump
2026-04-19.01:39:40 zfs destroy rpool/data-enc/subvol-115-disk-0@vzdump
2026-04-19.01:39:40 zfs snapshot rpool/data-enc/subvol-116-disk-0@vzdump
2026-04-19.01:39:40 zfs set pve-storage:refquota=10737418240 rpool/data-enc/subvol-116-disk-0@vzdump
2026-04-19.01:42:40 zfs destroy rpool/data-enc/subvol-116-disk-0@vzdump
2026-04-19.01:42:41 zfs snapshot rpool/data-enc/subvol-117-disk-0@vzdump
2026-04-19.01:42:41 zfs set pve-storage:refquota=4294967296 rpool/data-enc/subvol-117-disk-0@vzdump
2026-04-19.01:43:53 zfs destroy rpool/data-enc/subvol-117-disk-0@vzdump
```

# 6. Proxmox node configuration

### pveversion

```
proxmox-ve: 9.1.0 (running kernel: 6.17.13-2-pve)
pve-manager: 9.1.7 (running version: 9.1.7/16b139a017452f16)
proxmox-kernel-helper: 9.0.4
proxmox-kernel-6.17: 6.17.13-2
proxmox-kernel-6.17.13-2-pve-signed: 6.17.13-2
proxmox-kernel-6.17.13-1-pve-signed: 6.17.13-1
proxmox-kernel-6.17.9-1-pve-signed: 6.17.9-1
proxmox-kernel-6.17.4-2-pve-signed: 6.17.4-2
proxmox-kernel-6.17.2-1-pve-signed: 6.17.2-1
ceph-fuse: 19.2.3-pve2
corosync: 3.1.10-pve2
criu: 4.1.1-1
frr-pythontools: 10.4.1-1+pve1
ifupdown2: 3.3.0-1+pmx12
intel-microcode: 3.20251111.1~deb13u1
ksm-control-daemon: 1.5-1
libjs-extjs: 7.0.0-5
libproxmox-acme-perl: 1.7.1
libproxmox-backup-qemu0: 2.0.2
libproxmox-rs-perl: 0.4.1
libpve-access-control: 9.0.6
libpve-apiclient-perl: 3.4.2
libpve-cluster-api-perl: 9.1.1
libpve-cluster-perl: 9.1.1
libpve-common-perl: 9.1.9
libpve-guest-common-perl: 6.0.2
libpve-http-server-perl: 6.0.5
libpve-network-perl: 1.2.5
libpve-rs-perl: 0.11.4
libpve-storage-perl: 9.1.1
libspice-server1: 0.15.2-1+b1
lvm2: 2.03.31-2+pmx1
lxc-pve: 6.0.5-4
lxcfs: 6.0.4-pve1
novnc-pve: 1.6.0-3
proxmox-backup-client: 4.1.5-1
proxmox-backup-file-restore: 4.1.5-1
proxmox-backup-restore-image: 1.0.0
proxmox-firewall: 1.2.1
proxmox-kernel-helper: 9.0.4
proxmox-mail-forward: 1.0.2
proxmox-mini-journalreader: 1.6
proxmox-offline-mirror-helper: 0.7.3
proxmox-widget-toolkit: 5.1.9
pve-cluster: 9.1.1
pve-container: 6.1.2
pve-docs: 9.1.2
pve-edk2-firmware: 4.2025.05-2
pve-esxi-import-tools: 1.0.1
pve-firewall: 6.0.4
pve-firmware: 3.18-2
pve-ha-manager: 5.1.3
pve-i18n: 3.7.0
pve-qemu-kvm: 10.1.2-7
pve-xtermjs: 5.5.0-3
qemu-server: 9.1.6
smartmontools: 7.4-pve1
spiceterm: 3.4.1
swtpm: 0.8.0+pve3
vncterm: 1.9.1
zfsutils-linux: 2.4.1-pve1
```

### pvesm status

```
Name              Type     Status     Total (KiB)      Used (KiB) Available (KiB)        %
PVE-Backup        cifs     active       960784480        39142096       921642384    4.07%
local              dir     active       163632896         2358016       161274880    1.44%
local-zfs      zfspool     active       199592724        38317808       161274916   19.20%
```

### /etc/pve/storage.cfg

Path: `/etc/pve/storage.cfg`

```
dir: local
	path /var/lib/vz
	content vztmpl,backup,iso,import

zfspool: local-zfs
	pool rpool/data-enc
	content rootdir,images
	sparse 1

cifs: PVE-Backup
	path /mnt/pve/PVE-Backup
	server dns-320l
	share PVE-Backup
	content backup
	options vers=2.0
	prune-backups keep-all=1
	username proxmox

```

### /etc/pve/datacenter.cfg

Path: `/etc/pve/datacenter.cfg`

```
keyboard: it
```

### /etc/pve/user.cfg

Path: `/etc/pve/user.cfg`

```
user:homarr@pve:1:0::::::
token:homarr@pve!homarr:0:1::
user:root@pam:1:0:::savino.cannone@gmail.com:::

group:homarr:homarr@pve:homarr:



acl:1:/:@homarr,homarr@pve,homarr@pve!homarr:PVEAuditor:
```

### cluster status

```
not a cluster node or pvecm unavailable
```

# 7. systemd boot chain (ZFS-related)

## unit: zfs-import-cache.service

**systemctl show**

```
Requires=systemd-udev-settle.service system.slice
Wants=
Before=zfs-import.target
After=system.slice multipathd.service systemd-journald.socket systemd-remount-fs.service systemd-udev-settle.service cryptsetup.target
RequiresMountsFor=
LoadState=loaded
ActiveState=active
FragmentPath=/usr/lib/systemd/system/zfs-import-cache.service
UnitFileState=enabled
ConditionResult=yes
AssertResult=yes
```

**systemctl cat (first 120 lines)**

```
# /usr/lib/systemd/system/zfs-import-cache.service
[Unit]
Description=Import ZFS pools by cache file
Documentation=man:zpool(8)
DefaultDependencies=no
Requires=systemd-udev-settle.service
After=systemd-udev-settle.service
After=cryptsetup.target
After=multipathd.service
After=systemd-remount-fs.service
Before=zfs-import.target
ConditionFileNotEmpty=/etc/zfs/zpool.cache
ConditionPathIsDirectory=/sys/module/zfs

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=-/etc/default/zfs
ExecStart=/usr/sbin/zpool import -c /etc/zfs/zpool.cache -aN $ZPOOL_IMPORT_OPTS

[Install]
WantedBy=zfs-import.target

```

## unit: zfs-import-scan.service

**systemctl show**

```
Requires=systemd-udev-settle.service system.slice
Wants=
Before=zfs-import.target
After=multipathd.service system.slice systemd-journald.socket systemd-udev-settle.service cryptsetup.target
RequiresMountsFor=
LoadState=loaded
ActiveState=inactive
FragmentPath=/usr/lib/systemd/system/zfs-import-scan.service
UnitFileState=disabled
ConditionResult=no
AssertResult=no
```

**systemctl cat (first 120 lines)**

```
# /usr/lib/systemd/system/zfs-import-scan.service
[Unit]
Description=Import ZFS pools by device scanning
Documentation=man:zpool(8)
DefaultDependencies=no
Requires=systemd-udev-settle.service
After=systemd-udev-settle.service
After=cryptsetup.target
After=multipathd.service
Before=zfs-import.target
ConditionFileNotEmpty=!/etc/zfs/zpool.cache
ConditionPathIsDirectory=/sys/module/zfs

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=-/etc/default/zfs
ExecStart=/usr/sbin/zpool import -aN -d /dev/disk/by-id -o cachefile=none $ZPOOL_IMPORT_OPTS

[Install]
WantedBy=zfs-import.target

```

## unit: zfs-mount.service

**systemctl show**

```
Requires=system.slice
Wants=
Before=local-fs.target umount.target zfs-share.service
After=systemd-remount-fs.service mnt-_USB_PENDRIVE_KEY.mount system.slice zfs-load-all-keys-from-usb.service systemd-udev-settle.service systemd-journald.socket zfs-import.target
RequiresMountsFor=
LoadState=loaded
ActiveState=active
FragmentPath=/usr/lib/systemd/system/zfs-mount.service
UnitFileState=enabled
ConditionResult=yes
AssertResult=yes
```

**systemctl cat (first 120 lines)**

```
# /usr/lib/systemd/system/zfs-mount.service
[Unit]
Description=Mount ZFS filesystems
Documentation=man:zfs(8)
DefaultDependencies=no
After=systemd-udev-settle.service
After=zfs-import.target
After=systemd-remount-fs.service
Before=local-fs.target
ConditionPathIsDirectory=/sys/module/zfs

# This merely tells the service manager
# that unmounting everything undoes the
# effect of this service. No extra logic
# is ran as a result of these settings.
Conflicts=umount.target
Before=umount.target

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=-/etc/default/zfs
ExecStart=/usr/sbin/zfs mount -a

[Install]
WantedBy=zfs.target

```

## unit: zfs-load-key.service

**systemctl show**

```
Requires=
Wants=
Before=
After=
RequiresMountsFor=
LoadState=masked
ActiveState=inactive
FragmentPath=/usr/lib/systemd/system/zfs-load-key.service
UnitFileState=masked
ConditionResult=no
AssertResult=no
```

**systemctl cat (first 120 lines)**

```
# Unit zfs-load-key.service is masked.

```

## unit: zfs-load-all-keys-from-usb.service

**systemctl show**

```
Requires=system.slice mnt-_USB_PENDRIVE_KEY.mount zfs-import.target
Wants=
Before=zfs-mount.service
After=system.slice systemd-journald.socket mnt-_USB_PENDRIVE_KEY.mount -.mount zfs-import.target
RequiresMountsFor=/mnt/_USB_PENDRIVE_KEY
LoadState=loaded
ActiveState=inactive
FragmentPath=/etc/systemd/system/zfs-load-all-keys-from-usb.service
UnitFileState=enabled
ConditionResult=yes
AssertResult=yes
```

**systemctl cat (first 120 lines)**

```
# /etc/systemd/system/zfs-load-all-keys-from-usb.service
[Unit]
Description=Load all ZFS encryption keys after USB key mount
DefaultDependencies=no
# Order: zfs-import -> (USB mount via RequiresMountsFor) -> load-key -> zfs-mount -> ...
# Never use After=local-fs.target here: zfs-mount.service is ordered Before=local-fs.target.
# Combining After=local-fs and Before=zfs-mount is unsatisfiable and systemd can skip
# zfs-mount (zfs mount -a never runs; CT rootfs paths stay wrong / "dataset is busy").
After=zfs-import.target
Requires=zfs-import.target
RequiresMountsFor=/mnt/_USB_PENDRIVE_KEY
Before=zfs-mount.service
ConditionPathIsMountPoint=/mnt/_USB_PENDRIVE_KEY

[Service]
Type=oneshot
ExecStart=/usr/sbin/zfs load-key -a
TimeoutStartSec=120

[Install]
WantedBy=zfs.target

# Installation notes:
# - Ensure the USB device is mounted at /mnt/_USB_PENDRIVE_KEY before this service runs.
# - If using /etc/fstab, this unit uses RequiresMountsFor=/mnt/_USB_PENDRIVE_KEY
#   and does not depend on a specific generated .mount unit name.
# - Copy this file to /etc/systemd/system/zfs-load-all-keys-from-usb.service
# - Then run: systemctl daemon-reload && systemctl enable --now zfs-load-all-keys-from-usb.service

```

## unit: zfs.target

**systemctl show**

```
Requires=
Wants=zfs-mount.service zfs-share.service zfs-import.target zfs-volumes.target zfs-load-all-keys-from-usb.service zfs-zed.service
Before=multi-user.target shutdown.target
After=zfs-zed.service zfs-share.service zfs-volumes.target zfs-import.target
RequiresMountsFor=
LoadState=loaded
ActiveState=active
FragmentPath=/usr/lib/systemd/system/zfs.target
UnitFileState=enabled
ConditionResult=yes
AssertResult=yes
```

**systemctl cat (first 120 lines)**

```
# /usr/lib/systemd/system/zfs.target
[Unit]
Description=ZFS startup target

[Install]
WantedBy=multi-user.target

```

## unit: local-fs.target

**systemctl show**

```
Requires=mnt-_USB_PENDRIVE_KEY.mount
Wants=systemd-remount-fs.service run-lock.mount tmp.mount
Before=console-setup.service systemd-sysext.service ldconfig.service systemd-sysext.socket systemd-machine-id-commit.service rpc-svcgssd.service pvefw-logger.service sysinit.target systemd-journal-catalog-update.service apparmor.service systemd-tmpfiles-setup.service networking.service pvebanner.service systemd-update-done.service systemd-tmpfiles-clean.service rpc-statd-notify.service systemd-binfmt.service pvenetcommit.service systemd-confext.service
After="rpool-data\\x2denc-subvol\\x2d100\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d102\\x2ddisk\\x2d0.mount" var-lib-lxcfs.mount "rpool-data\\x2denc-subvol\\x2d110\\x2ddisk\\x2d0.mount" tmp.mount "rpool-data\\x2denc-subvol\\x2d109\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d116\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d108\\x2ddisk\\x2d0.mount" local-fs-pre.target "rpool-data\\x2denc-subvol\\x2d117\\x2ddisk\\x2d0.mount" mnt-_USB_PENDRIVE_KEY.mount systemd-fsck-root.service var-lib-vz.mount "rpool-data\\x2denc-subvol\\x2d113\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d101\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d115\\x2ddisk\\x2d0.mount" run-user-0.mount run-lock.mount "rpool-data\\x2denc-subvol\\x2d107\\x2ddisk\\x2d0.mount" zfs-mount.service "rpool-data\\x2denc-subvol\\x2d106\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d112\\x2ddisk\\x2d0.mount" rpool.mount rpool-ROOT.mount "rpool-data\\x2denc.mount" "rpool-data\\x2denc-subvol\\x2d105\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d104\\x2ddisk\\x2d0.mount" systemd-quotacheck-root.service "rpool-data\\x2denc-subvol\\x2d114\\x2ddisk\\x2d0.mount" "rpool-data\\x2denc-subvol\\x2d111\\x2ddisk\\x2d0.mount" etc-pve.mount "rpool-data\\x2denc-subvol\\x2d103\\x2ddisk\\x2d0.mount" systemd-remount-fs.service
RequiresMountsFor=
LoadState=loaded
ActiveState=active
FragmentPath=/usr/lib/systemd/system/local-fs.target
UnitFileState=static
ConditionResult=yes
AssertResult=yes
```

**systemctl cat (first 120 lines)**

```
# /usr/lib/systemd/system/local-fs.target
#  SPDX-License-Identifier: LGPL-2.1-or-later
#
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.

[Unit]
Description=Local File Systems
Documentation=man:systemd.special(7)

DefaultDependencies=no
After=local-fs-pre.target
Conflicts=shutdown.target
OnFailure=emergency.target
OnFailureJobMode=replace-irreversibly

```

## unit: multi-user.target

**systemctl show**

```
Requires=basic.target
Wants=proxmox-boot-cleanup.service lxc-monitord.service rrdcached.service avahi-daemon.service smartmontools.service pve-cluster.service pve-lxc-syscalld.service getty.target pve-firewall-commit.service postfix.service pve-sdn-commit.service cron.service remote-fs.target proxmox-firewall.service pve-query-machine-capabilities.service pvefw-logger.service console-setup.service pvedaemon.service rbdmap.service pvestatd.service pveproxy.service zramswap.service e2scrub_reap.service ceph.target rpcbind.service lxc.service qmeventd.service systemd-user-sessions.service ksmtuned.service spiceproxy.service systemd-ask-password-wall.path dbus.service chrony.service lxcfs.service systemd-logind.service lxc-net.service ssh.service pvescheduler.service zfs.target networking.service grub-common.service pve-guests.service nfs-client.target pve-firewall.service
Before=graphical.target shutdown.target xfs_scrub_all.service
After=smartmontools.service systemd-user-sessions.service getty.target zfs.target zramswap.service dbus.service pve-guests.service lxc-net.service basic.target ceph.target e2scrub_reap.service lxcfs.service ksmtuned.service pvestatd.service ssh.service proxmox-boot-cleanup.service lxc-monitord.service qmeventd.service rbdmap.service postfix.service grub-common.service pveproxy.service pvescheduler.service rrdcached.service spiceproxy.service proxmox-firewall.service pve-lxc-syscalld.service rescue.target nfs-client.target pve-query-machine-capabilities.service pvedaemon.service avahi-daemon.service rescue.service cron.service lxc.service chrony.service systemd-logind.service systemd-networkd.service
RequiresMountsFor=
LoadState=loaded
ActiveState=active
FragmentPath=/usr/lib/systemd/system/multi-user.target
UnitFileState=static
ConditionResult=yes
AssertResult=yes
```

**systemctl cat (first 120 lines)**

```
# /usr/lib/systemd/system/multi-user.target
#  SPDX-License-Identifier: LGPL-2.1-or-later
#
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.

[Unit]
Description=Multi-User System
Documentation=man:systemd.special(7)
Requires=basic.target
Conflicts=rescue.service rescue.target
After=basic.target rescue.service rescue.target
AllowIsolate=yes

```

### systemctl list-dependencies zfs.target

```bash
systemctl list-dependencies zfs.target --no-pager 2>/dev/null | head -n 200
```

```
zfs.target
○ ├─zfs-load-all-keys-from-usb.service
● ├─zfs-mount.service
● ├─zfs-share.service
● ├─zfs-zed.service
● ├─zfs-import.target
● │ └─zfs-import-cache.service
● └─zfs-volumes.target
●   └─zfs-volume-wait.service
```

### systemctl list-dependencies zfs-mount.service

```bash
systemctl list-dependencies zfs-mount.service --no-pager 2>/dev/null | head -n 120
```

```
zfs-mount.service
● └─system.slice
```

### systemd-analyze critical-chain (multi-user.target)

```bash
systemd-analyze critical-chain multi-user.target --no-pager 2>/dev/null | head -n 80 || true
```

```
The time when unit became active or started is printed after the "@" character.
The time the unit took to start is printed after the "+" character.

multi-user.target @1min 6.485s
└─pvescheduler.service @1min 4.197s +2.285s
  └─pve-guests.service @11.715s +52.468s
    └─118.scope @59.484s
      └─qemu.slice @59.475s
        └─-.slice @187ms
```

# 8. ZFS / initramfs hooks and dracut (if present)

### ls /etc/zfs

```
total 47
drwxr-xr-x  4 root root    6 Mar 31 16:25 .
drwxr-xr-x 98 root root  191 Apr 18 18:19 ..
drwxr-xr-x  2 root root   17 Mar 31 16:25 zed.d
-rw-r--r--  1 root root 9651 Mar 17 13:22 zfs-functions
-rw-r--r--  1 root root 1656 Apr 18 17:10 zpool.cache
drwxr-xr-x  2 root root   44 Mar 31 16:24 zpool.d
```

### /etc/zfs/zfs-list.cache

Path not present or not readable: `/etc/zfs/zfs-list.cache`

### ls initramfs-tools conf

```
total 10
drwxr-xr-x 2 root root  3 Apr 12 21:54 .
drwxr-xr-x 5 root root  8 Nov 18 20:04 ..
-rw-r--r-- 1 root root 85 Nov 18 19:08 pve-initramfs.conf
```

### ls dracut conf

```

```

# 9. Network (basics)

### ip -brief

```bash
ip -br a 2>/dev/null || true
```

```
lo               UNKNOWN        127.0.0.1/8 ::1/128 
nic0             UP             
wlp1s0           DOWN           
vmbr0            UP             192.168.10.37/24 fe80::2001:12ff:fea1:1e1/64 
veth101i0@if2    UP             
veth100i0@if2    UP             
veth102i0@if2    UP             
veth104i0@if2    UP             
veth105i0@if2    UP             
veth103i0@if2    UP             
veth106i0@if2    UP             
veth108i0@if2    UP             
veth107i0@if2    UP             
veth109i0@if2    UP             
veth110i0@if2    UP             
veth111i0@if2    UP             
veth112i0@if2    UP             
veth113i0@if2    UP             
veth114i0@if2    UP             
fwbr112i0        UP             
fwpr112p0@fwln112i0 UP             
fwln112i0@fwpr112p0 UP             
veth116i0@if2    UP             
veth115i0@if2    UP             
veth117i0@if2    UP             
tap118i0         UNKNOWN        
```

### /etc/network/interfaces

Path: `/etc/network/interfaces`

```
# network interface settings; autogenerated
# Please do NOT modify this file directly, unless you know what
# you're doing.
#
# If you want to manage parts of the network configuration manually,
# please utilize the 'source' or 'source-directory' directives to do
# so.
# PVE will preserve these directives, but will NOT read its network
# configuration from sourced files, so do not attempt to move any of
# the PVE managed interfaces into external files!

auto lo
iface lo inet loopback

iface nic0 inet manual

iface nic1 inet manual

iface nic2 inet manual

iface wlp1s0 inet manual

auto vmbr0
iface vmbr0 inet static
	address 192.168.10.37/24
	gateway 192.168.10.1
	bridge-ports nic0
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes
	bridge-vids 2-4094

source /etc/network/interfaces.d/*
```

# 10. Disk health (non-intrusive SMART identity)

### smartctl --scan

```
/dev/nvme0 -d nvme # /dev/nvme0, NVMe device
```

# 11. Recent boot journal (errors, capped)

### journalctl this boot (priority err, 200 lines)

```bash
journalctl -b -p err --no-pager -n 200 2>/dev/null || true
```

```
Apr 18 23:54:49 pve kernel: atkbd serio0: Failed to enable keyboard on isa0060/serio0
Apr 18 23:54:50 pve kernel: sof-audio-pci-intel-icl 0000:00:1f.3: SOF firmware and/or topology file not found.
Apr 18 23:54:50 pve kernel: sof-audio-pci-intel-icl 0000:00:1f.3: error: sof_probe_work failed err: -2
Apr 18 23:54:55 pve blkmapd[868]: open pipe file /run/rpc_pipefs/nfs/blocklayout failed: No such file or directory
Apr 19 00:11:30 pve pveproxy[25779]: got inotify poll request in wrong process - disabling inotify
Apr 19 01:43:56 pve pvescheduler[106192]: VM 118 qga command failed - VM 118 qga command 'guest-ping' failed - got timeout
```

# End of report

---

Report written to: `/root/encryption/proxmox-migration-report-pve-20260419-092039.md`