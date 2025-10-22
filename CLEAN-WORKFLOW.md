# Clean Netboot to SD Provisioning Workflow

## Goal
Boot 5 Raspberry Pis with blank SD cards → They install Raspberry Pi OS Lite to SD → They reboot and boot from SD going forward

## EEPROM Configuration
- **Boot Order:** `0xf12`
  - Try SD card first (`1`)
  - Fall back to network boot if SD fails (`2`)

## The Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                      NETBOOT SERVER (10.10.10.231)                    │
├──────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  TFTP Boot Files: /opt/netboot/config/menus/[serial]/                │
│  ├── start4.elf, fixup4.dat (GPU firmware)                           │
│  ├── kernel8.img, initrd.img (Linux kernel)                          │
│  ├── config.txt, cmdline.txt (boot config)                           │
│  └── overlays/ (device tree overlays)                                 │
│                                                                        │
│  NFS Root Filesystem: /srv/nfs/raspios-pi/                           │
│  ├── Complete Raspberry Pi OS Lite installation                      │
│  ├── /boot/firmware/ (copy of TFTP boot files)                       │
│  ├── /usr/local/bin/provision-sd.sh (provisioning script)            │
│  └── /etc/systemd/system/provision-sd-card.service                   │
│                                                                        │
└──────────────────────────────────────────────────────────────────────┘
```

## Boot Flow

### First Boot (Blank SD Card)

```
1. Pi powers on with blank SD card
   ↓
2. EEPROM tries SD card → No bootable files found
   ↓
3. EEPROM falls back to network boot
   ↓
4. DHCP provides: IP address + TFTP server (10.10.10.231)
   ↓
5. TFTP: Pi downloads boot files from /opt/netboot/config/menus/[serial]/
   ↓
6. GPU firmware loads kernel8.img with cmdline.txt parameters
   ↓
7. cmdline.txt says: root=/dev/nfs nfsroot=10.10.10.231:/srv/nfs/raspios-pi
   ↓
8. Linux kernel mounts NFS root as /
   ↓
9. Systemd starts
   ↓
10. provision-sd-card.service runs automatically
    ↓
11. Checks: Does /boot/firmware/.sd-provisioned exist?
    → NO (SD card is blank)
    ↓
12. provision-sd.sh runs:
    - Partitions SD card (512MB boot FAT32 + ext4 root)
    - Formats partitions
    - Copies NFS root → SD root partition (~5-10 min)
    - Copies /boot/firmware/ → SD boot partition
    - Updates cmdline.txt: root=PARTUUID=xxxxx (point to SD)
    - Creates .sd-provisioned marker
    - Reboots
```

### Subsequent Boots (Provisioned SD Card)

```
1. Pi powers on with provisioned SD card
   ↓
2. EEPROM tries SD card → FOUND bootable files!
   ↓
3. GPU firmware loads start4.elf, kernel8.img FROM SD CARD
   ↓
4. cmdline.txt says: root=PARTUUID=xxxxx (SD card root partition)
   ↓
5. Linux kernel mounts SD card as /
   ↓
6. Systemd starts
   ↓
7. provision-sd-card.service checks: Does .sd-provisioned exist?
   → YES (already provisioned)
   ↓
8. Service exits immediately, does nothing
   ↓
9. Pi boots normally from SD card ✓
```

## Ansible Playbooks

### 1. Initial Setup: `rpi-netboot.yml`

**Purpose:** Set up the complete netboot infrastructure

**What it does:**
1. Downloads Raspberry Pi OS Lite image
2. Extracts and copies to NFS root (`/srv/nfs/raspios-pi/`)
3. Configures NFS exports
4. **Installs and configures TFTP server (tftpd-hpa)**
5. Downloads and deploys TFTP boot files to `/opt/netboot/config/menus/[serial]/`
6. **Syncs boot files from TFTP → NFS root `/boot/firmware/`**
7. Configures SSH, passwords, hostname service

**Run:**
```bash
./run-playbook.sh rpi-netboot.yml
```

**Run once:** When setting up the infrastructure initially

---

### 2. Enable SD Provisioning: `enable-sd-provisioning.yml`

**Purpose:** Install the self-provisioning service into the NFS root

**What it does:**
1. Syncs boot files from TFTP → NFS root (ensures `/boot/firmware/` has complete files)
2. Copies `provision-sd.sh` to NFS root `/usr/local/bin/`
3. Installs `provision-sd-card.service` systemd service
4. Enables the service to run on boot

**Run:**
```bash
./run-playbook.sh enable-sd-provisioning.yml
```

**Run once:** After initial setup, to enable auto-provisioning

---

### 3. Update Hostname: `update-hostname.yml`

**Purpose:** Update hostname configuration in NFS root

**What it does:**
- Reconfigures hostname service in NFS root

**Run:**
```bash
./run-playbook.sh update-hostname.yml
```

**Run:** If you need to change hostname mappings

---

## Key Files

### On Netboot Server

**TFTP Boot Files** (per-Pi directories):
```
/opt/netboot/config/menus/
├── 94a418cd/          # pi-01
│   ├── start4.elf
│   ├── fixup4.dat
│   ├── kernel8.img
│   ├── initrd.img
│   ├── config.txt
│   ├── cmdline.txt    # Points to NFS: root=/dev/nfs nfsroot=...
│   └── overlays/
├── 54ab2151/          # pi-02
├── 101af127/          # pi-03
├── c56a6028/          # pi-04
└── ea4cc994/          # pi-05
```

**NFS Root Filesystem** (shared by all Pis during network boot):
```
/srv/nfs/raspios-pi/
├── bin/, sbin/, usr/, etc/, ... (complete OS)
├── boot/firmware/     # Boot files (synced from TFTP)
│   ├── start4.elf, fixup4.dat, kernel8.img, initrd.img
│   ├── config.txt, cmdline.txt
│   └── overlays/
├── usr/local/bin/
│   └── provision-sd.sh   # Self-provisioning script
└── etc/systemd/system/
    └── provision-sd-card.service
```

### On Provisioned Pi (SD Card)

**SD Card Boot Partition** (`/dev/mmcblk0p1` mounted at `/boot/firmware`):
```
/boot/firmware/
├── start4.elf, fixup4.dat   # GPU firmware
├── kernel8.img, initrd.img  # Linux kernel
├── config.txt               # Boot configuration
├── cmdline.txt              # Points to SD: root=PARTUUID=xxxxx
├── overlays/                # Device tree overlays
└── .sd-provisioned          # Marker file (prevents re-provisioning)
```

**SD Card Root Partition** (`/dev/mmcblk0p2` mounted at `/`):
```
/ (complete copy of NFS root)
├── bin/, sbin/, usr/, etc/, ...
├── etc/hostname             # Unique hostname (pi-01, pi-02, etc.)
└── etc/fstab                # Points to SD partitions
```

**Note:** Provisioning service is REMOVED from SD card after provisioning completes

---

## The Critical Fix

### The Problem
The NFS root's `/boot/firmware/` was nearly empty (only 3 files). When the provisioning script copied `/boot/firmware/*` to the SD card, it was copying incomplete boot files.

### The Solution
Added task: `sync-boot-to-nfs.yml`

This syncs COMPLETE boot files from TFTP → NFS root:
```
/opt/netboot/config/menus/94a418cd/*
                    ↓
         (rsync with --exclude cmdline.txt)
                    ↓
/srv/nfs/raspios-pi/boot/firmware/*
```

Now when `provision-sd.sh` runs and copies `/boot/firmware/*` to SD, it gets COMPLETE boot files.

---

## Step-by-Step Deployment

### Initial Setup (Run Once)

```bash
cd /home/spencer/mounts/wd1tb/Users/Spencer/repos/homelab-infra/rpi-netboot

# 1. Deploy complete netboot infrastructure
./run-playbook.sh rpi-netboot.yml

# 2. Enable SD auto-provisioning
./run-playbook.sh enable-sd-provisioning.yml
```

### Provision Pis

```bash
# Option A: All at once
# Power on all 5 Pis with blank SD cards
# Wait ~10 minutes
# All will be provisioned and booting from SD

# Option B: One at a time (recommended for first time)
# Power on one Pi, wait for it to provision and reboot
# Verify it boots from SD
# Repeat for next Pi
```

### Verification

```bash
# SSH to a provisioned Pi
ssh pi@<pi-ip>

# Check boot source (should be SD card)
findmnt -n -o SOURCE /
# Expected: /dev/mmcblk0p2

# Check hostname (should be unique)
hostname
# Expected: pi-01, pi-02, pi-03, pi-04, or pi-05

# Check provision marker exists
ls -la /boot/firmware/.sd-provisioned
# Should exist

# Check cmdline points to SD
cat /boot/firmware/cmdline.txt
# Should have: root=PARTUUID=xxxxx
# Should NOT have: root=/dev/nfs
```

---

## Troubleshooting

### Pi still boots from NFS after provisioning

**Check boot files in NFS root:**
```bash
ssh pi@10.10.10.231
ls -la /srv/nfs/raspios-pi/boot/firmware/start4.elf
# Should exist (not missing)
```

**Fix:** Re-run boot file sync:
```bash
./run-playbook.sh rpi-netboot.yml --tags sync-boot
./run-playbook.sh enable-sd-provisioning.yml
```

### Re-provision a Pi

```bash
# SSH to Pi (while booted from SD or NFS)
ssh pi@<pi-ip>

# Remove provision marker
sudo mount /dev/mmcblk0p1 /mnt 2>/dev/null || true
sudo rm -f /mnt/.sd-provisioned
sudo umount /mnt 2>/dev/null || true

# Reboot
sudo reboot

# Pi will detect unprovision and re-run provisioning
```

---

## What Gets Removed (No Longer Needed)

- ❌ `provision-to-sd.yml` - Old Ansible-based provisioning (deleted)
- ❌ Any manual SSH-based provisioning workflows
- ❌ Confusion about NFS vs SD boot

## What's Kept

- ✅ `rpi-netboot.yml` - Initial infrastructure setup
- ✅ `enable-sd-provisioning.yml` - Enable self-provisioning
- ✅ `provision-sd.sh` - Self-provisioning script
- ✅ `provision-sd-card.service` - Systemd service
- ✅ `sync-boot-to-nfs.yml` - Boot file sync (critical fix)

## Summary

**Single workflow:**
1. Run `rpi-netboot.yml` once (sets up infrastructure)
2. Run `enable-sd-provisioning.yml` once (enables auto-provisioning)
3. Power on Pis with blank SD cards
4. They auto-provision themselves (~10 min)
5. They boot from SD card going forward

**No more confusion!**
