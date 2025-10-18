# Raspberry Pi Network Boot - Ansible

Enterprise-grade Ansible automation for Raspberry Pi network boot infrastructure.

## Directory Structure

```
ansible/
├── inventory.yml              # Server inventory
├── group_vars/
│   ├── all.yml               # Centralized configuration variables
│   └── vault.yml             # Encrypted sensitive data (SSH keys, passwords)
├── playbooks/                # All playbooks
│   ├── rpi-netboot.yml      # Main network boot setup
│   └── deploy-auto-provision.yml  # Auto-provisioning service
├── tasks/                    # Reusable task files
│   ├── nfs-root-setup.yml
│   ├── nfs-root-config.yml
│   ├── tftp-boot-deploy.yml
│   └── status-summary.yml
├── templates/                # Jinja2 templates
│   ├── config.txt.j2
│   └── cmdline.txt.j2
└── VAULT.md                  # Vault usage documentation
```

## Security Note

Sensitive data (SSH keys, passwords) are stored in `group_vars/vault.yml` and encrypted with Ansible Vault. See [VAULT.md](VAULT.md) for details on managing encrypted variables.

## Usage

### Running from Docker (Windows/macOS)

All commands should be run from the `ansible/` directory:

```bash
cd ansible/

# Main network boot setup (with vault)
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

# Deploy auto-provisioning service (with vault)
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
    ansible-playbook -i inventory.yml playbooks/deploy-auto-provision.yml \
    --vault-password-file /tmp/vault_pass \
    --ssh-common-args="-o StrictHostKeyChecking=no"'
```

### Running from Linux/Native

```bash
cd ansible/

# Main network boot setup (with vault password prompt)
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --ask-vault-pass
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml -e "@group_vars/vault.yml"
# Or with vault password file
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --vault-password-file .vault_pass

# Deploy auto-provisioning service
ansible-playbook -i inventory.yml playbooks/deploy-auto-provision.yml --ask-vault-pass

# Run with tags
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --tags nfs
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --tags tftp
```

## Configuration

Edit `group_vars/all.yml` to configure:
- Netboot server IP and credentials
- NFS export paths
- TFTP boot paths
- Raspberry Pi devices (serial numbers and hostnames)
- Boot configuration (HDMI, UART, etc.)
- Default credentials

## Adding New Raspberry Pis

Simply add to `group_vars/all.yml`:

```yaml
raspberry_pis:
  - serial: "94a418cd"
    hostname: "pi-01"
    description: "First Pi"
  - serial: "54ab2151"  # Add new entries here
    hostname: "pi-02"
    description: "Second Pi"
```

Then re-run the playbook. The auto-provisioning service will handle new Pis automatically on first boot!

## Available Tags

**rpi-netboot.yml:**
- `nfs` - NFS-related tasks
- `setup` - Initial setup tasks
- `config` - Configuration tasks
- `tftp` - TFTP boot file tasks
- `boot` - Boot file deployment
- `cleanup` - Cleanup tasks
- `status` - Status and summary

**deploy-auto-provision.yml:**
- `deploy` - Script and service deployment
- `template` - Template directory setup
- `service` - SystemD service configuration
- `status` - Status and summary

## Idempotency

All playbooks are designed to be idempotent - you can run them multiple times safely without causing issues. See `docs/IDEMPOTENCY.md` for details.

## Auto-Provisioning

The auto-provisioning service monitors TFTP logs and automatically provisions new Pis. See `docs/AUTO-PROVISIONING.md` for details.
