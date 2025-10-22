#!/bin/bash
# Helper script to run Ansible playbooks with Docker

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if playbook argument provided
if [ $# -eq 0 ]; then
    echo "Usage: ./run-playbook.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --setup                      Setup complete infrastructure (NFS + TFTP)"
    echo "  --nfs-only                   Setup only NFS root filesystem"
    echo "  --boot-only                  Deploy only boot files to TFTP"
    echo "  --enable-sd-provisioning     Enable SD card auto-provisioning"
    echo "  --enable-auto-provision      Enable dynamic TFTP auto-provisioning"
    echo "  --tags TAGS                  Run specific tasks (e.g., --tags nfs,tftp)"
    echo ""
    echo "Examples:"
    echo "  ./run-playbook.sh --setup                      # Full setup"
    echo "  ./run-playbook.sh --nfs-only                   # NFS only"
    echo "  ./run-playbook.sh --boot-only                  # TFTP boot files only"
    echo "  ./run-playbook.sh --enable-sd-provisioning     # Enable SD provisioning"
    echo "  ./run-playbook.sh --enable-auto-provision      # Enable auto TFTP provisioning"
    echo "  ./run-playbook.sh --tags config                # Run config tasks only"
    echo ""
    exit 1
fi

PLAYBOOK="playbooks/rpi-netboot.yml"
TAGS=""
EXTRA_ARGS=""

# Parse arguments
case "$1" in
    --setup)
        # Run everything
        PLAYBOOK="playbooks/rpi-netboot.yml"
        TAGS=""
        ;;
    --nfs-only)
        PLAYBOOK="playbooks/rpi-netboot.yml"
        TAGS="--tags nfs"
        ;;
    --boot-only)
        PLAYBOOK="playbooks/rpi-netboot.yml"
        TAGS="--tags tftp"
        ;;
    --enable-sd-provisioning)
        PLAYBOOK="playbooks/enable-sd-provisioning.yml"
        TAGS=""
        ;;
    --enable-auto-provision)
        PLAYBOOK="playbooks/enable-auto-provision.yml"
        TAGS=""
        ;;
    --tags)
        PLAYBOOK="playbooks/rpi-netboot.yml"
        TAGS="--tags $2"
        shift
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run './run-playbook.sh' for usage information"
        exit 1
        ;;
esac

# Check if SSH key exists
if [ ! -f "$HOME/.ssh/raspberrypi_rsa" ]; then
    echo "Error: SSH key not found at ~/.ssh/raspberrypi_rsa"
    echo "Please create SSH key pair first"
    exit 1
fi

# Check if ansible-playbook is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook not found"
    echo "Please install Ansible first: pip install ansible"
    exit 1
fi

echo "Running playbook: $PLAYBOOK $TAGS"
echo "Working directory: $SCRIPT_DIR/ansible"
echo ""

# Run Ansible directly
cd "$SCRIPT_DIR/ansible"

# Check if vault file is encrypted
if head -1 group_vars/all/vault.yml 2>/dev/null | grep -q '\$ANSIBLE_VAULT'; then
    # Vault file is encrypted, need password
    if [ -f "$HOME/.vault_pass" ]; then
        echo "Using vault password from ~/.vault_pass"
        ansible-playbook -i inventory.yml "$PLAYBOOK" $TAGS $EXTRA_ARGS --vault-password-file "$HOME/.vault_pass"
    elif [ -f ".vault_pass" ]; then
        echo "Using vault password from .vault_pass"
        ansible-playbook -i inventory.yml "$PLAYBOOK" $TAGS $EXTRA_ARGS --vault-password-file .vault_pass
    else
        echo "Vault file is encrypted. Please enter vault password when prompted."
        ansible-playbook -i inventory.yml "$PLAYBOOK" $TAGS $EXTRA_ARGS --ask-vault-pass
    fi
else
    # Vault file is not encrypted, no password needed
    echo "Note: vault.yml is not encrypted (plain text)"
    ansible-playbook -i inventory.yml "$PLAYBOOK" $TAGS $EXTRA_ARGS
fi

echo ""
echo "Playbook completed successfully!"
