# Quick Start Guide - Raspberry Pi Network Boot

Complete setup in 3 steps! This guide gets you from zero to network-booting Raspberry Pis in ~15 minutes.

## Prerequisites

### 1. SSH Key Setup
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/raspberrypi_rsa -C "pi@netboot"
```

### 2. Docker Running
Ensure Docker Desktop is running (for Windows/macOS users)

### 3. Network Access
Can you reach the netboot server?
```bash
ping 10.10.10.231
```

## Initial Setup

### Step 1: Configure Your Pis

Edit `ansible/group_vars/all.yml`:

```yaml
# Add your Pi serial numbers
raspberry_pis:
  - serial: "94a418cd"    # Get from: cat /proc/cpuinfo | grep Serial
    hostname: "pi-01"
    description: "First Pi"
  - serial: "XXXXXXXX"    # Add more Pis here
    hostname: "pi-02"
    description: "Second Pi"
```

**Getting Serial Numbers:**
- Boot Pi with SD card: `cat /proc/cpuinfo | grep Serial`
- Or check CPU chip label on Pi
- Use first 8 hex characters

### Step 2: Configure Vault (Security)

```bash
cd ansible/group_vars

# Copy example vault
cp vault.yml.example vault.yml

# Edit with your SSH public key
vim vault.yml
# Add your public key from: cat ~/.ssh/raspberrypi_rsa.pub

# Encrypt it
ansible-vault encrypt vault.yml
# Enter a strong password and remember it!
```

### Step 3: Deploy Everything

**From Docker (Windows/macOS):**

```bash
cd ansible/

# Full deployment (NFS + TFTP + Config)
docker run --rm \
  -v "c:/Users/Spencer/.ssh/raspberrypi_rsa:/tmp/key:ro" \
  -v "$(pwd)/..:/workspace:ro" \
  -e ANSIBLE_VAULT_PASSWORD="your-vault-password" \
  cytopia/ansible:latest-tools sh -c '\
    mkdir -p /root/.ssh && \
    cp /tmp/key /root/.ssh/raspberrypi_rsa && \
    chmod 600 /root/.ssh/raspberrypi_rsa && \
    cd /workspace/ansible && \
    echo "$ANSIBLE_VAULT_PASSWORD" > /tmp/vault_pass && \
    ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
    --vault-password-file /tmp/vault_pass \
    --ssh-common-args="-o StrictHostKeyChecking=no"'
```

**From Linux/Native Ansible:**

```bash
cd ansible/

# Full deployment
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --ask-vault-pass
```

**Time:** ~10-15 minutes (first run, includes OS download)

## Boot Your Pis

1. **Insert blank SD card** (or SD with network boot enabled)
2. **Connect Ethernet cable** to network
3. **Power on Pi**
4. **Wait ~60-90 seconds** for first boot

## Access Your Pis

### Find Pi IP Addresses

**Quick scan:**
```bash
nmap -sn 10.10.10.0/24
```

**Or check DHCP server logs**

### SSH Access (Primary)

```bash
ssh -i ~/.ssh/raspberrypi_rsa pi@10.10.10.230
```

### Console Access (Fallback)

1. Connect HDMI monitor + USB keyboard
2. Wait for login prompt
3. Login: `pi` / `raspberry`

## Common Operations

### Add More Raspberry Pis

**1. Get serial number:**
```bash
# On running Pi
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip> \
  "cat /proc/cpuinfo | grep Serial | awk '{print \$3}' | tail -c 9"
```

**2. Add to inventory:**
Edit `ansible/group_vars/all.yml`:
```yaml
raspberry_pis:
  - serial: "94a418cd"
    hostname: "pi-01"
    description: "First Pi"
  - serial: "XXXXXXXX"    # Add new Pi
    hostname: "pi-02"
    description: "Second Pi"
```

**3. Deploy boot files:**
```bash
# Only deploy TFTP boot files (fast)
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags tftp --ask-vault-pass
```

**4. Power on new Pi!**

### Update Configuration on All Pis

**Edit config, then deploy:**
```bash
# Edit configuration
vim ansible/group_vars/all.yml

# Deploy to all Pis
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags tftp,config --ask-vault-pass
```

**Reboot all Pis (parallel!):**
```bash
# Create inventory of your Pis
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

Since Pis share NFS root, install on one = install on all:

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
# Ping test
ansible all -i pi_hosts.yml -m ping

# Uptime
ansible all -i pi_hosts.yml -a "uptime"

# Disk space
ansible all -i pi_hosts.yml -a "df -h /"

# Memory usage
ansible all -i pi_hosts.yml -a "free -h"
```

### Update All Pis

```bash
# Update packages on shared NFS root
ssh -i ~/.ssh/raspberrypi_rsa pi@10.10.10.230
sudo apt update && sudo apt upgrade -y

# Reboot all Pis
ansible all -i pi_hosts.yml -m reboot --become
```

## Incremental Deployments

### NFS Root Only (Update OS)

```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags nfs --ask-vault-pass
```

### TFTP Boot Files Only (Add Pis)

```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags tftp --ask-vault-pass
```

### Configuration Only (Update settings)

```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags config --ask-vault-pass
```

### Status Check Only

```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags status --ask-vault-pass
```

## Deploy Auto-Provisioning

Enable automatic provisioning of new Pis:

```bash
cd ansible/

ansible-playbook -i inventory.yml playbooks/deploy-auto-provision.yml \
  --ask-vault-pass
```

Now when you power on a new Pi, it automatically gets provisioned! No manual serial collection needed.

## Troubleshooting

### Pi Doesn't Network Boot

**Check EEPROM boot order:**
```bash
# On Pi (booted from SD)
vcgencmd bootloader_config
# Look for: BOOT_ORDER=0xf241 (includes network boot)
```

**Enable network boot:**
```bash
sudo raspi-config
# Advanced Options → Boot Order → Network Boot
```

### HDMI Console Black Screen

**Verify VC4 driver enabled:**
```bash
# On netboot server
ssh pi@10.10.10.231 "cat /opt/netboot/config/menus/94a418cd/config.txt | grep vc4"
# Should show: dtoverlay=vc4-kms-v3d
```

**Redeploy if missing:**
```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags tftp --ask-vault-pass
```

### Console Login Fails

SSH works but console doesn't? Password needs setting:

```bash
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip>
echo 'pi:raspberry' | sudo chpasswd
```

### NFS Mount Fails

**Check NFS export:**
```bash
ssh pi@10.10.10.231 "sudo exportfs -v"
# Should show: /srv/nfs/raspios-pi *(rw,sync,no_subtree_check,no_root_squash)
```

**Re-run NFS setup:**
```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
  --tags nfs --ask-vault-pass
```

### Can't Find Pi IP Address

**Create inventory dynamically:**
```bash
# Scan network
nmap -sn 10.10.10.0/24 -oG - | grep "Up" | awk '{print $2}'

# Or use Ansible discovery (if you know one Pi IP)
ansible-playbook -i "10.10.10.230," -m setup all
```

## Security Checklist

Before going to production:

- [ ] Change default password in vault.yml
- [ ] Rotate SSH keys periodically
- [ ] Use firewall rules to limit access
- [ ] Consider VPN for remote access
- [ ] Set up monitoring/alerting
- [ ] Backup ansible/ directory regularly

## Quick Reference

### Key Files
- `ansible/group_vars/all.yml` - Configuration (non-sensitive)
- `ansible/group_vars/vault.yml` - Secrets (encrypted)
- `ansible/inventory.yml` - Netboot server
- `ansible/playbooks/rpi-netboot.yml` - Main playbook

### Key Commands
```bash
# Full deployment
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --ask-vault-pass

# Quick updates
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --tags tftp --ask-vault-pass

# Reboot all Pis
ansible all -i pi_hosts.yml -m reboot --become

# Check all Pis
ansible all -i pi_hosts.yml -m ping
```

### Key Locations (on server)
- NFS Root: `/srv/nfs/raspios-pi/`
- TFTP Boot: `/opt/netboot/config/menus/<serial>/`
- NFS Exports: `/etc/exports`

### Default Credentials
- SSH: Key authentication (pi user)
- Console: pi / raspberry (⚠️ change!)

## Next Steps

1. ✅ Pis are network booting
2. ⏭️ Deploy auto-provisioning service
3. ⏭️ Set up static IPs or DHCP reservations
4. ⏭️ Install required software on NFS root
5. ⏭️ Set up monitoring (Prometheus/Grafana)
6. ⏭️ Configure backups
7. ⏭️ Document your runbooks

## Advanced: Ansible Tips

### Run Commands on All Pis in Parallel

```bash
# Run any command
ansible all -i pi_hosts.yml -a "hostname"

# With sudo
ansible all -i pi_hosts.yml -a "systemctl status ssh" --become

# Copy files
ansible all -i pi_hosts.yml -m copy -a "src=./script.sh dest=/tmp/script.sh mode=0755"

# Install packages
ansible all -i pi_hosts.yml -m apt -a "name=htop state=present" --become
```

### Limit to Specific Pis

```bash
# Only pi-01
ansible-playbook -i pi_hosts.yml playbook.yml --limit pi-01

# Only pi-01 and pi-02
ansible-playbook -i pi_hosts.yml playbook.yml --limit "pi-01,pi-02"

# All except pi-03
ansible-playbook -i pi_hosts.yml playbook.yml --limit 'all:!pi-03'
```

### Dry Run (Check Mode)

```bash
# See what would change without making changes
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --check --ask-vault-pass
```

## Support

- **README.md** - Complete technical documentation
- **STRUCTURE.md** - Repository organization
- **ansible/README.md** - Ansible-specific docs
- **ansible/VAULT.md** - Vault usage guide
- **SECURITY.md** - Security best practices

**Ready to scale!** 🚀
