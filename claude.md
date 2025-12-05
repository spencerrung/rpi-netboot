# Claude Context: Raspberry Pi Network Boot Infrastructure

## Project Overview

This repository provides a production-ready Ansible automation system for diskless network booting of Raspberry Pi 4B devices from a central NFS server with TFTP boot. All Raspberry Pis boot from the same shared NFS root filesystem, with per-device boot configurations.

**Key Concept**: Multiple Raspberry Pis boot over the network (no SD card needed) and share a single NFS root filesystem, making software installation and updates instant across all devices.

## Architecture

```
Pi (blank SD) → DHCP → TFTP (firmware/kernel) → NFS (root filesystem)
```

**Network Boot Server**: `10.10.10.231`
- **TFTP**: Serves per-Pi boot files from `/opt/netboot/config/menus/[serial]/`
- **NFS**: Serves shared root filesystem from `/srv/nfs/raspios-pi`

## Repository Structure

```
rpi-netboot/
├── run-playbook.sh              # Main deployment script
├── README.md                    # User documentation
├── QUICKSTART.md                # Beginner guide
├── STRUCTURE.md                 # Detailed structure
├── claude.md                    # This file
│
├── ansible/
│   ├── inventory.yml            # Ansible hosts (netboot server)
│   ├── group_vars/
│   │   └── all/
│   │       ├── main.yml         # All configuration variables
│   │       └── vault.yml        # Encrypted secrets (passwords, SSH keys)
│   ├── playbooks/
│   │   ├── rpi-netboot.yml      # Main deployment playbook
│   │   ├── deploy-auto-provision.yml
│   │   ├── enable-auto-provision.yml
│   │   ├── enable-sd-provisioning.yml
│   │   └── update-hostname.yml
│   ├── tasks/                   # Modular task files
│   │   ├── nfs-root-setup.yml   # Download/extract Raspberry Pi OS
│   │   ├── nfs-root-config.yml  # Configure NFS root (SSH, passwords)
│   │   ├── tftp-boot-deploy.yml # Deploy per-Pi boot files
│   │   └── ...
│   ├── templates/
│   │   ├── config.txt.j2        # Pi boot configuration template
│   │   └── cmdline.txt.j2       # Kernel cmdline template
│   └── files/
│       ├── auto-provision-pi.sh # Auto-provisioning script
│       └── provision-sd.sh      # SD card provisioning
│
├── scripts/                     # Utility scripts
└── docs/                        # Additional documentation
```

## Key Configuration Files

### `ansible/group_vars/all/main.yml`
**The single source of truth for all configuration**. Contains:
- Network settings (`netboot_server_ip`, NFS/TFTP paths)
- Raspberry Pi inventory (`raspberry_pis` list with serial numbers)
- Boot configuration (`boot_config`, `kernel_cmdline`)
- Image URLs and versions

**Important**: All Pi serial numbers must be added here before deployment.

### `ansible/group_vars/all/vault.yml`
**Encrypted secrets** (use `ansible-vault edit`):
- `vault_pi_password` - Console password for 'pi' user
- `vault_ssh_public_key` - SSH public key for remote access

### `ansible/inventory.yml`
**Ansible inventory** defining the netboot server:
```yaml
netboot_servers:
  hosts:
    pi-netboot-server:
      ansible_host: 10.10.10.231
      ansible_user: pi
```

### Templates: `ansible/templates/*.j2`
**Jinja2 templates** that generate per-Pi configuration files:
- `config.txt.j2` → Boot configuration (GPU, HDMI, overlays)
- `cmdline.txt.j2` → Kernel command line (NFS mount, cgroups for K3s)

## Important Concepts

### 1. Serial Numbers
Each Raspberry Pi is identified by its **CPU serial number** (first 8 hex chars):
```bash
cat /proc/cpuinfo | grep Serial
# Output: Serial : 1000000094a418cd
# Use: 94a418cd
```

Serial numbers are used for:
- Unique TFTP boot directories: `/opt/netboot/config/menus/94a418cd/`
- Hostname mapping in `raspberry_pis` list

### 2. Shared NFS Root
**Critical**: All Pis share `/srv/nfs/raspios-pi` as their root filesystem.
- Installing software on one Pi = installed on ALL Pis
- Changes to shared root persist across reboots
- Per-Pi state (hostname, IP) comes from kernel cmdline/DHCP

### 3. HDMI Console (vc4-kms-v3d)
**Essential**: `dtoverlay=vc4-kms-v3d` enables working HDMI console.
- Without it: Black screen or rainbow splash only
- With it: Proper GPU→Linux handoff, console login works

This was a critical discovery for emergency console access.

### 4. Kubernetes/K3s Support
Kernel cmdline includes cgroup parameters required for K3s:
```yaml
cgroup_enable_cpuset: true
cgroup_memory: 1
cgroup_enable_memory: true
```

### 5. Auto-Provisioning
A systemd service on the netboot server automatically:
1. Detects new Pi serial numbers from DHCP/TFTP logs
2. Adds them to configuration
3. Deploys boot files

See `docs/AUTO-PROVISIONING.md` for details.

## Ansible Tags

The playbooks use tags for granular control:

| Tag | Purpose | Example Use Case |
|-----|---------|------------------|
| `setup` | Initial setup tasks | First-time NFS root download |
| `nfs` | All NFS-related tasks | Setup shared root filesystem |
| `tftp` | All TFTP boot tasks | Deploy per-Pi boot files |
| `config` | Configuration tasks | Update SSH keys, passwords |
| `cleanup` | Cleanup temporary files | After deployment |
| `status` | Show deployment status | Verify configuration |

## Common Tasks

### Adding a New Raspberry Pi
1. **Get serial**: Boot Pi once (any OS), run `cat /proc/cpuinfo | grep Serial`
2. **Add to config**: Edit `ansible/group_vars/all/main.yml`:
   ```yaml
   raspberry_pis:
     - serial: "12345678"
       hostname: "pi-06"
       description: "New Pi"
   ```
3. **Deploy boot files**: `./run-playbook.sh --boot-only`
4. **Network boot**: Power on the Pi (blank SD card or network boot enabled)

### Updating Boot Configuration
1. **Edit variables**: Modify `ansible/group_vars/all/main.yml`:
   ```yaml
   boot_config:
     hdmi_force_hotplug: 1
     # Add new settings
   ```
2. **Or edit templates**: Modify `ansible/templates/config.txt.j2` for advanced changes
3. **Deploy**: `./run-playbook.sh --boot-only`
4. **Reboot Pis**: Required for changes to take effect

### Installing Software on All Pis
```bash
# SSH to any Pi
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip>

# Install packages (affects shared NFS root)
sudo apt update && sudo apt install -y htop docker.io

# Software now available on ALL network-booted Pis!
```

### Changing Pi Password
```bash
# Edit vault
ansible-vault edit ansible/group_vars/all/vault.yml
# Update vault_pi_password

# Re-run config tasks
cd ansible/
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --tags config --ask-vault-pass
```

### Full Deployment (First Time)
```bash
./run-playbook.sh --setup
```
Downloads Raspberry Pi OS (~500MB), configures NFS/TFTP, deploys all boot files.

## Development Guidelines

### When Modifying Playbooks
1. **Read existing tasks first**: Understand idempotency patterns
2. **Use tags appropriately**: Add relevant tags to new tasks
3. **Test incrementally**: Use specific tags to test changes
4. **Preserve idempotency**: Ensure tasks can run multiple times safely
5. **Update documentation**: Keep README.md and this file in sync

### When Adding Variables
1. **Add to main.yml**: All variables go in `ansible/group_vars/all/main.yml`
2. **Secrets go in vault.yml**: Encrypt with `ansible-vault edit`
3. **Use descriptive names**: Follow existing naming conventions
4. **Add comments**: Explain what the variable controls
5. **Provide defaults**: Make playbooks work without user changes when possible

### When Editing Templates
1. **Preserve existing settings**: Boot configs are fragile
2. **Use variables from main.yml**: Don't hardcode values
3. **Test on one Pi first**: Wrong boot config = Pi won't boot
4. **Document special settings**: Explain why something is needed (e.g., vc4-kms-v3d)

### Testing Changes
```bash
# Dry run (check mode)
cd ansible/
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --check

# Run specific tag
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --tags tftp --ask-vault-pass

# Verbose mode for debugging
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml -vvv
```

## Critical Files (Don't Break!)

### `/srv/nfs/raspios-pi/` (on netboot server)
**The shared root filesystem**. Breaking this breaks ALL Pis.
- Backup before major changes
- Test changes on one Pi before deploying widely

### `/opt/netboot/config/menus/[serial]/config.txt`
**Boot configuration per Pi**. Wrong config = Pi won't boot.
- Always include `dtoverlay=vc4-kms-v3d` for HDMI console
- Test boot config changes on one Pi first

### `/opt/netboot/config/menus/[serial]/cmdline.txt`
**Kernel command line**. Must include correct NFS root parameters.
- NFS server IP must be correct
- NFS path must exist
- Cgroup parameters needed for K3s

## Troubleshooting Guide

### Pi doesn't network boot
- Check EEPROM boot order: `vcgencmd bootloader_config` (look for `BOOT_ORDER` with `0x2`)
- Enable network boot: `sudo raspi-config` → Advanced → Boot Order → Network Boot
- Verify DHCP is providing PXE parameters
- Check TFTP logs on netboot server

### HDMI console is black
- Verify `dtoverlay=vc4-kms-v3d` in `/opt/netboot/config/menus/[serial]/config.txt`
- Redeploy boot files: `./run-playbook.sh --boot-only`
- Check HDMI cable and monitor

### NFS mount fails
- Check NFS export: `ssh pi@10.10.10.231 'sudo exportfs -v'`
- Verify firewall allows NFS (port 2049)
- Check network connectivity from Pi to NFS server
- Look at kernel messages during boot (add `debug` to cmdline.txt)

### SSH works but console login fails
- Password not set correctly with `chpasswd`
- Re-run: `./run-playbook.sh --tags config`
- Or manually: `echo 'pi:raspberry' | sudo chpasswd`

### Playbook fails with vault errors
- Run with `--ask-vault-pass`
- Verify vault.yml is encrypted: `head ansible/group_vars/all/vault.yml`
- Decrypt to edit: `ansible-vault edit ansible/group_vars/all/vault.yml`

## Useful Commands

### Ansible
```bash
# Run full deployment
./run-playbook.sh --setup

# Run with specific tags
./run-playbook.sh --tags nfs,tftp

# NFS only
./run-playbook.sh --nfs-only

# Boot files only
./run-playbook.sh --boot-only

# Check syntax
cd ansible/
ansible-playbook playbooks/rpi-netboot.yml --syntax-check

# List all tags
ansible-playbook playbooks/rpi-netboot.yml --list-tags

# List all tasks
ansible-playbook playbooks/rpi-netboot.yml --list-tasks
```

### Managing Pis
```bash
# Create Pi inventory
cat > pi_hosts.yml <<EOF
all:
  hosts:
    pi-01:
      ansible_host: 10.10.10.230
  vars:
    ansible_user: pi
    ansible_ssh_private_key_file: ~/.ssh/raspberrypi_rsa
EOF

# Ping all Pis
ansible all -i pi_hosts.yml -m ping

# Reboot all Pis
ansible all -i pi_hosts.yml -m reboot --become

# Run command on all
ansible all -i pi_hosts.yml -a "uptime"

# Install package on all
ansible all -i pi_hosts.yml -m apt -a "name=htop state=present" --become
```

### Git Operations
```bash
# Current branch: claude/add-claude-md-01S6Xm6Un8gbktLFxUo4JLk3
# Always develop on this branch

# Commit changes
git add .
git commit -m "Descriptive message"

# Push to remote (use -u for first push)
git push -u origin claude/add-claude-md-01S6Xm6Un8gbktLFxUo4JLk3
```

## Design Decisions & Rationale

### Why Shared NFS Root?
**Pros**:
- Install software once, available everywhere
- Easy centralized management
- Saves disk space
- Quick updates

**Cons**:
- No per-Pi filesystem isolation
- NFS server is single point of failure
- Network dependency

**Decision**: Benefits outweigh drawbacks for clustered workloads (like K3s).

### Why TFTP for Boot Files?
- Pi firmware requires TFTP for network boot
- Each Pi needs unique config.txt/cmdline.txt (hostname, serial-specific settings)
- TFTP is standard for PXE boot

### Why Ansible?
- Idempotent: Safe to run multiple times
- Declarative: Describe desired state, not steps
- Templating: Jinja2 templates for per-Pi customization
- Modular: Tasks can be reused and tagged
- Agentless: No software needed on target hosts

### Why vc4-kms-v3d?
- Modern KMS (Kernel Mode Setting) driver
- Proper GPU→kernel handoff for HDMI console
- Without it, HDMI output stops after GPU firmware stage
- Required for emergency console access when SSH fails

## Security Considerations

### Current Security Posture
- **SSH**: Key-based authentication (good)
- **Console**: Password `raspberry` (⚠️ change for production!)
- **NFS**: `no_root_squash` allows root on Pis to modify NFS root (necessary but risky)
- **Network**: No encryption (NFS v3, TFTP unencrypted)
- **Secrets**: Ansible vault for passwords/keys (good)

### Recommendations for Production
1. **Change default password**: Edit `vault_pi_password` in vault.yml
2. **Firewall NFS/TFTP**: Only allow from Pi network
3. **Consider NFSv4 with Kerberos**: For encrypted/authenticated NFS
4. **Backup NFS root**: Regular backups of `/srv/nfs/raspios-pi`
5. **Monitor access**: Log SSH access, watch for unauthorized changes

## Performance Notes

### Network Boot Speed
- First boot: ~60-90 seconds (firmware download, NFS mount)
- Subsequent boots: ~30-45 seconds (TFTP cached)
- Boot speed depends on network quality

### NFS Performance
- Gigabit Ethernet recommended
- NFS v3 (no auth overhead, good for trusted networks)
- Consider local caching for read-heavy workloads

### Ansible Deployment Time
- Full setup (first time): ~10-15 minutes (Raspberry Pi OS download)
- Boot files only: ~30 seconds
- Config changes: ~10 seconds

## Future Enhancements

### Potential Improvements
- [ ] Per-Pi NFS roots for isolation
- [ ] Automated testing (molecule)
- [ ] Monitoring/metrics for Pis
- [ ] Automatic backup/restore
- [ ] Web UI for management
- [ ] UEFI network boot support

### Maintenance Tasks
- Update Raspberry Pi OS version: Change `raspios_version` in main.yml
- Update Pi firmware: Change URLs in `pi_firmware_files`
- Rotate SSH keys: Update vault.yml, redeploy with `--tags config`

## Resources & References

### Official Documentation
- [Raspberry Pi Network Boot](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#network-booting)
- [Ansible Documentation](https://docs.ansible.com/)
- [NFS Documentation](https://nfs.sourceforge.net/)

### Internal Documentation
- `README.md` - User-facing overview and reference
- `QUICKSTART.md` - Step-by-step beginner guide
- `STRUCTURE.md` - Detailed repository structure
- `CLEAN-WORKFLOW.md` - Deployment workflow guide
- `docs/AUTO-PROVISIONING.md` - Auto-provisioning system service
- `docs/IDEMPOTENCY.md` - Idempotency best practices

## Quick Reference Card

```bash
# Common operations
./run-playbook.sh --setup          # First-time full setup
./run-playbook.sh --nfs-only       # Update NFS root only
./run-playbook.sh --boot-only      # Update boot files only
./run-playbook.sh --tags config    # Update configuration only

# Get Pi serial number
cat /proc/cpuinfo | grep Serial | awk '{print substr($3, length($3)-7)}'

# Edit secrets
ansible-vault edit ansible/group_vars/all/vault.yml

# Check NFS exports
ssh pi@10.10.10.231 'sudo exportfs -v'

# Backup NFS root
ssh pi@10.10.10.231 'sudo tar czf ~/backup.tar.gz -C /srv/nfs raspios-pi'

# Reboot all Pis
ansible all -i pi_hosts.yml -m reboot --become
```

## Getting Help

When working with this codebase:
1. **Read the documentation**: README.md has detailed usage info
2. **Check task files**: Look at `ansible/tasks/*.yml` for implementation details
3. **Test incrementally**: Use tags to run small changes
4. **Ask for clarification**: Better to ask than to break the NFS root!
5. **Review git history**: See why decisions were made

## Notes for Claude

- **Always read before modifying**: Don't change Ansible tasks without understanding existing patterns
- **Respect idempotency**: Ensure tasks can run multiple times safely
- **Use existing patterns**: Follow conventions in existing playbooks
- **Test with tags**: Recommend testing with `--tags` before full runs
- **Document changes**: Update README.md and this file when adding features
- **Be cautious with NFS root**: Changes affect ALL Pis simultaneously
- **Verify boot configs**: Wrong config.txt = Pi won't boot
- **Remember vc4-kms-v3d**: Critical for HDMI console
- **Consider the user**: Provide commands they can run, not just explanations
