# Repository Structure

## Overview

This `rpi-netboot` directory contains all the configuration needed to set up and manage Raspberry Pi network boot infrastructure.

## Directory Structure

```
rpi-netboot/
├── README.md                           # Complete documentation
├── QUICKSTART.md                       # Quick start guide
├── STRUCTURE.md                        # This file - repository structure
├── .gitignore                          # Git ignore rules (SSH keys, etc.)
├── run-playbook.sh                     # Helper script to run playbooks
│
├── ansible/                            # Ansible automation
│   ├── rpi-netboot.yml                 # Main unified playbook
│   ├── inventory.yml                   # Ansible inventory for netboot server
│   ├── group_vars/
│   │   └── all.yml                     # Centralized configuration
│   └── templates/
│       ├── config.txt.j2               # Pi boot configuration template
│       └── cmdline.txt.j2              # Kernel command line template
│
├── scripts/                            # Utility scripts
│   └── auto-provision-pi.sh           # Auto-provisioning daemon
│
└── docs/                               # Additional documentation
    └── IDEMPOTENCY.md                 # Idempotency documentation
```

## File Purposes

### Core Documentation
- **README.md** - Complete technical documentation, architecture, troubleshooting
- **QUICKSTART.md** - Step-by-step guide for getting started quickly
- **STRUCTURE.md** - This file, explains repository organization

### Configuration Files
- **.gitignore** - Prevents committing sensitive files (SSH keys, etc.)

### Scripts
- **run-playbook.sh** - Wrapper script to run Ansible playbooks with Docker
  - Usage: `./run-playbook.sh --setup` or `./run-playbook.sh --boot-only`

### Ansible Directory
- **ansible/rpi-netboot.yml** - Main unified playbook
  - NFS root filesystem setup
  - TFTP boot files deployment
  - Tag-based execution for granular control

- **ansible/inventory.yml** - Ansible inventory defining the netboot server (10.10.10.231)

- **ansible/group_vars/all.yml** - Centralized configuration
  - Network settings
  - Raspberry Pi list (serials, hostnames)
  - Boot configuration
  - Kernel parameters
  - Credentials

- **ansible/templates/** - Jinja2 templates
  - **config.txt.j2** - Pi boot configuration (generated per Pi)
  - **cmdline.txt.j2** - Kernel command line (generated per Pi)

## Quick Usage

### First Time Setup
```bash
cd rpi-netboot
./run-playbook.sh --setup        # Full setup (NFS + TFTP)
# OR
./run-playbook.sh --nfs-only     # NFS only
./run-playbook.sh --boot-only    # TFTP only
```

### Adding New Pis
1. Edit `ansible/group_vars/all.yml` - add Pi to `raspberry_pis` list
2. Run `./run-playbook.sh --boot-only`
3. Network boot the new Pi

## What's Configured Where

### On Netboot Server (10.10.10.231)
- `/srv/nfs/raspios-pi/` - NFS root filesystem (shared by all Pis)
- `/opt/netboot/config/menus/<serial>/` - Per-Pi boot files via TFTP
- `/etc/exports` - NFS export configuration

### Per-Pi Boot Files (TFTP)
Each Pi gets its own directory under `/opt/netboot/config/menus/<serial>/`:
- `config.txt` - Boot configuration (VC4 KMS driver, HDMI settings)
- `cmdline.txt` - Kernel parameters (NFS root, console)
- `kernel8.img` - Linux kernel
- `initrd.img` - Initial ramdisk
- `start4.elf` - GPU firmware
- `fixup4.dat` - GPU firmware
- `bootcode.bin` - Bootloader
- `bcm2711-rpi-4-b.dtb` - Device tree
- `overlays/` - Device tree overlays

## Key Configuration Values

### Network
- Netboot Server: `10.10.10.231`
- NFS Root: `10.10.10.231:/srv/nfs/raspios-pi`
- TFTP Path: `/opt/netboot/config/menus`

### Credentials
- SSH: Key-based authentication (`~/.ssh/raspberrypi_rsa`)
- Console: pi / raspberry

### Pi Serials (edit in playbooks/fix-pi-boot.yml)
Currently configured:
- `94a418cd` - First Pi

## What We Solved

### Critical Technical Solutions
1. **HDMI Console** - `dtoverlay=vc4-kms-v3d` enables proper display handoff
2. **Console Login** - Use `chpasswd` instead of direct shadow editing
3. **Network Boot** - Proper NFS v3 configuration with no_root_squash
4. **Multiple Pis** - Per-serial TFTP directories for device-specific configs

### Working Features
- ✅ Zero-touch network boot from blank SD card
- ✅ SSH access with key authentication
- ✅ HDMI console for emergency fallback
- ✅ Shared NFS root for all Pis
- ✅ Fully automated via Ansible
