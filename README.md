# Raspberry Pi Network Boot Infrastructure

Professional Ansible automation for diskless Raspberry Pi network boot using NFS + TFTP.

## Overview

This repository provides a complete, production-ready infrastructure for network booting Raspberry Pi 4B devices from a central NFS server with TFTP boot. All configuration is managed through Ansible with Jinja2 templates for easy customization.

## Features

- ✅ **Zero-touch network boot** from blank SD card
- ✅ **Centralized configuration** using Ansible variables and templates
- ✅ **Multi-Pi support** with per-device boot configurations
- ✅ **SSH access** with key authentication
- ✅ **HDMI console** for emergency fallback access
- ✅ **Tag-based deployment** for granular control
- ✅ **Fully idempotent** - safe to run multiple times without side effects

## Architecture

```
┌─────────────────┐
│  Raspberry Pi   │
│  (blank SD)     │
└────────┬────────┘
         │ 1. DHCP Request
         ▼
┌─────────────────┐
│  DHCP Server    │──── IP, TFTP server, boot filename
└────────┬────────┘
         │ 2. TFTP Download
         ▼
┌─────────────────┐
│  TFTP Server    │──── firmware, kernel, initrd, config.txt
│  10.10.10.231   │      (/opt/netboot/config/menus/[serial]/)
└────────┬────────┘
         │ 3. NFS Mount
         ▼
┌─────────────────┐
│  NFS Server     │──── Root filesystem (/srv/nfs/raspios-pi)
│  10.10.10.231   │
└─────────────────┘
```

## Repository Structure

```
rpi-netboot/
├── run-playbook.sh              # Helper script
├── README.md                    # This file
├── QUICKSTART.md                # Quick start guide
├── STRUCTURE.md                 # Repository structure
│
├── ansible/                     # Ansible automation
│   ├── rpi-netboot.yml          # Main playbook
│   ├── inventory.yml            # Ansible inventory
│   ├── group_vars/
│   │   └── all.yml              # Centralized configuration
│   └── templates/
│       ├── config.txt.j2        # Pi boot configuration
│       └── cmdline.txt.j2       # Kernel command line
│
├── scripts/                     # Utility scripts
└── docs/                        # Additional documentation
```

## Quick Start

### Prerequisites

1. **SSH Key**: Create if you don't have one
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/raspberrypi_rsa -C "pi@netboot"
   ```

2. **Docker**: Ensure Docker Desktop is running (or just bash with ansible installed)

3. **Network**: Access to netboot server (mine is 10.10.10.231)

### Configuration

Edit `ansible/group_vars/all.yml` to customize:

```yaml
# Add your Raspberry Pis
raspberry_pis:
  - serial: "94a418cd"          # cat /proc/cpuinfo | grep Serial
    hostname: "pi-01"
    description: "First Pi"
  - serial: "XXXXXXXX"          # Add more Pis here
    hostname: "pi-02"
    description: "Second Pi"

# Update if needed
pi_password: "raspberry"         # Change for production!
ssh_public_key: "ssh-rsa ..."   # Your SSH public key
```

### Deployment

#### Full Setup (First Time)
```bash
cd rpi-netboot
./run-playbook.sh --setup
```

This will:
- Download and extract Raspberry Pi OS (~500MB)
- Configure NFS export
- Deploy boot files to TFTP for all Pis
- Setup SSH keys and passwords

**Time**: ~10-15 minutes (first run)

#### Incremental Deployments

```bash
# NFS root only
./run-playbook.sh --nfs-only

# Boot files only (when adding Pis)
./run-playbook.sh --boot-only

# Specific tasks only
./run-playbook.sh --tags config
```

### Network Boot Your Pi

1. Insert blank SD card (or card with network boot bootcode.bin)
2. Connect Pi to network via Ethernet
3. Power on
4. Wait ~60-90 seconds for first boot

### Access Your Pi

**SSH (Primary):**
```bash
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip>
```

**Console (Fallback):**
- Connect HDMI + keyboard
- Login: `pi` / `raspberry`

## Configuration Files

### ansible/group_vars/all.yml

Central configuration for all variables:

```yaml
# Network
netboot_server_ip: "10.10.10.231"
nfs_root_base: "/srv/nfs"
tftp_root: "/opt/netboot/config/menus"

# Raspberry Pis
raspberry_pis:
  - serial: "94a418cd"
    hostname: "pi-01"
    description: "First Pi"

# Boot configuration
boot_config:
  dtoverlay: "vc4-kms-v3d"      # Required for HDMI console!
  enable_uart: 1
  hdmi_force_hotplug: 1

# Kernel parameters
kernel_cmdline:
  console: "tty1"
  root: "/dev/nfs"
  nfsroot: "{{ netboot_server_ip }}:{{ raspios_root_dir }},vers=3,tcp"
```

### Templates

**ansible/templates/config.txt.j2:**
```jinja
# Generated for {{ item.hostname }} ({{ item.serial }})
arm_64bit={{ boot_config.arm_64bit }}
dtoverlay={{ boot_config.dtoverlay }}
hdmi_force_hotplug={{ boot_config.hdmi_force_hotplug }}
...
```

**ansible/templates/cmdline.txt.j2:**
```jinja
console={{ kernel_cmdline.console }} root={{ kernel_cmdline.root }} ...
```

## Adding More Raspberry Pis

### 1. Get Pi Serial Number
  #### This part is only for adding to the inventory the serial is
  #### automatically found with the system service running on the netboot server.

On a running Pi:
```bash
cat /proc/cpuinfo | grep Serial
# Output: Serial : 100000001234abcd
# Use first 8 chars: 10000000
```

### 2. Add to Configuration

Edit `ansible/group_vars/all.yml`:
```yaml
raspberry_pis:
  - serial: "94a418cd"
    hostname: "pi-01"
    description: "First Pi"
  - serial: "10000000"          # New Pi
    hostname: "pi-02"
    description: "Second Pi"
```

### 3. Deploy Boot Files

```bash
./run-playbook.sh --boot-only
```

### 4. Network Boot

Power on the new Pi!

## Ansible Tags

The playbook uses tags for granular control:

| Tag | Description | Use Case |
|-----|-------------|----------|
| `nfs` | All NFS-related tasks | Setup NFS root |
| `tftp` | All TFTP boot tasks | Deploy boot files |
| `setup` | Initial setup tasks | First-time setup |
| `config` | Configuration tasks | Update configs only |
| `cleanup` | Cleanup temporary files | After deployment |
| `status` | Show status/summary | Check deployment |

**Examples:**
```bash
# Run only NFS setup
./run-playbook.sh --tags nfs

# Run only TFTP deployment
./run-playbook.sh --tags tftp

# Run setup and config
./run-playbook.sh --tags setup,config

# Check status
./run-playbook.sh --tags status
```

## Technical Details

### Why VC4 KMS Driver?

The `dtoverlay=vc4-kms-v3d` setting is **critical** for HDMI console:

- **Without it**: Rainbow splash or black screen, no console text
- **With it**: Proper GPU→Linux handoff, working console login

This was the key discovery that enabled reliable console access for mission-critical deployments.

### Network Boot Process

1. **Pi EEPROM**: Broadcasts DHCP with PXE parameters
2. **DHCP**: Responds with TFTP server IP and boot filename
3. **TFTP**: Pi downloads start4.elf, config.txt, kernel, initrd
4. **GPU Firmware**: Loads kernel with NFS root parameters
5. **Kernel**: Mounts NFS, starts systemd
6. **Services**: SSH and getty start

### Files Deployed

**NFS Server:**
- `/srv/nfs/raspios-pi/*` - Complete Raspberry Pi OS root
- `/etc/exports` - NFS export config

**TFTP Server (per Pi):**
- `/opt/netboot/config/menus/[serial]/config.txt`
- `/opt/netboot/config/menus/[serial]/cmdline.txt`
- `/opt/netboot/config/menus/[serial]/kernel8.img`
- `/opt/netboot/config/menus/[serial]/initrd.img`
- `/opt/netboot/config/menus/[serial]/start4.elf`
- `/opt/netboot/config/menus/[serial]/fixup4.dat`
- `/opt/netboot/config/menus/[serial]/bootcode.bin`
- `/opt/netboot/config/menus/[serial]/bcm2711-rpi-4-b.dtb`
- `/opt/netboot/config/menus/[serial]/overlays/*`

## Troubleshooting

### Pi Doesn't Network Boot

**Check EEPROM boot order:**
```bash
vcgencmd bootloader_config  # Look for BOOT_ORDER with 0x2
```

**Enable network boot:**
```bash
sudo raspi-config
# Advanced Options → Boot Order → Network Boot
```

### HDMI Console Black Screen

**Verify VC4 KMS driver is enabled:**
```bash
# On netboot server
cat /opt/netboot/config/menus/<serial>/config.txt | grep vc4
# Should show: dtoverlay=vc4-kms-v3d
```

**Redeploy if missing:**
```bash
./run-playbook.sh --boot-only
```

### Console Login Fails (Password Rejected)

SSH works but console doesn't? Password needs to be set with `chpasswd`:

```bash
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip>
echo 'pi:raspberry' | sudo chpasswd
```

This is already handled in the playbook for new deployments.

### NFS Mount Fails

**Check NFS export:**
```bash
ssh pi@10.10.10.231
sudo exportfs -v
# Should show: /srv/nfs/raspios-pi *(rw,sync,no_subtree_check,no_root_squash)
```

**Re-run if needed:**
```bash
./run-playbook.sh --nfs-only
```

## Advanced Usage

### Custom Kernel Parameters

Edit `ansible/group_vars/all.yml`:
```yaml
kernel_cmdline:
  console: "tty1"
  root: "/dev/nfs"
  # Add custom parameters:
  loglevel: 7
  debug: true
```

### Per-Pi Custom Config

Modify templates to use `item` variable:
```jinja
# ansible/templates/config.txt.j2
{% if item.hostname == "pi-01" %}
# Special config for pi-01
hdmi_group=2
hdmi_mode=82
{% endif %}
```

### Multiple NFS Roots

For per-Pi isolation, create separate NFS roots:
```yaml
raspberry_pis:
  - serial: "94a418cd"
    hostname: "pi-01"
    nfs_root: "/srv/nfs/pi-01"  # Custom root
```

## Common Operations

### Update All Pi Boot Configs

**1. Edit configuration:**
```bash
vim ansible/group_vars/all.yml    # or ansible/templates/*.j2
```

**2. Deploy changes:**
```bash
cd ansible/
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --tags tftp --ask-vault-pass
```

**3. Reboot all Pis (parallel):**
```bash
# Create inventory for your Pis
cat > pi_hosts.yml <<EOF
all:
  hosts:
    pi-01:
      ansible_host: 10.10.10.230
    pi-02:
      ansible_host: 10.10.10.231
  vars:
    ansible_user: pi
    ansible_ssh_private_key_file: ~/.ssh/raspberrypi_rsa
EOF

# Reboot all at once
ansible all -i pi_hosts.yml -m reboot --become
```

### Install Software on All Pis

Since Pis share NFS root, installing on one affects all:

```bash
# Connect to any Pi
ssh -i ~/.ssh/raspberrypi_rsa pi@10.10.10.230

# Install software
sudo apt update
sudo apt install htop vim git

# Now available on ALL Pis!
```

### Check Status of All Pis

```bash
# Ping all Pis
ansible all -i pi_hosts.yml -m ping

# Get uptime
ansible all -i pi_hosts.yml -a "uptime"

# Check disk space
ansible all -i pi_hosts.yml -a "df -h /"

# Memory usage
ansible all -i pi_hosts.yml -a "free -h"

# System info
ansible all -i pi_hosts.yml -m setup -a "filter=ansible_distribution*"
```

### Run Commands on All Pis

```bash
# Restart service on all
ansible all -i pi_hosts.yml -a "systemctl restart ssh" --become

# Copy file to all
ansible all -i pi_hosts.yml -m copy -a "src=./config dest=/tmp/config mode=0644"

# Install package on all
ansible all -i pi_hosts.yml -m apt -a "name=htop state=present" --become

# Gather logs from all
ansible all -i pi_hosts.yml -a "journalctl -u ssh --since '1 hour ago'" --become
```

### Update All Pis

```bash
# Update packages on shared NFS root (updates all Pis)
ssh -i ~/.ssh/raspberrypi_rsa pi@10.10.10.230
sudo apt update && sudo apt upgrade -y

# Reboot all Pis to apply kernel updates
ansible all -i pi_hosts.yml -m reboot --become

# Wait for all to come back
ansible all -i pi_hosts.yml -m wait_for_connection -a "timeout=300"
```

### Backup NFS Root

**On netboot server:**
```bash
ssh pi@10.10.10.231
sudo tar czf ~/raspios-backup-$(date +%Y%m%d).tar.gz -C /srv/nfs raspios-pi
```

**Or with Ansible:**
```bash
ansible netboot_server -i inventory.yml -a \
  "tar czf /home/pi/raspios-backup-$(date +%Y%m%d).tar.gz -C /srv/nfs raspios-pi" \
  --become
```

## Default Credentials

**SSH:**
- Username: `pi`
- Auth: SSH key (`~/.ssh/raspberrypi_rsa`)

**Console:**
- Username: `pi`
- Password: `raspberry` (⚠️ change for production!)

## Support & Documentation

- **README.md** - This file (overview and reference)
- **QUICKSTART.md** - Step-by-step beginner guide
- **STRUCTURE.md** - Detailed repository structure
- **docs/AUTO-PROVISIONING.md** - System service that scrapes the pi serials
- **docs/IDEMPOTENCY.md** - Idempotency verification and best practices
- **ansible/group_vars/all.yml** - All configuration options (well commented)

## License

MIT License - Use freely for your infrastructure


