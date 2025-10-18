#!/bin/bash
# Helper script to run Ansible playbooks with Docker

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if playbook argument provided
if [ $# -eq 0 ]; then
    echo "Usage: ./run-playbook.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --setup         Setup complete infrastructure (NFS + TFTP)"
    echo "  --nfs-only      Setup only NFS root filesystem"
    echo "  --boot-only     Deploy only boot files to TFTP"
    echo "  --tags TAGS     Run specific tasks (e.g., --tags nfs,tftp)"
    echo ""
    echo "Examples:"
    echo "  ./run-playbook.sh --setup                # Full setup"
    echo "  ./run-playbook.sh --nfs-only             # NFS only"
    echo "  ./run-playbook.sh --boot-only            # TFTP boot files only"
    echo "  ./run-playbook.sh --tags config          # Run config tasks only"
    echo ""
    exit 1
fi

PLAYBOOK="rpi-netboot.yml"
TAGS=""
EXTRA_ARGS=""

# Parse arguments
case "$1" in
    --setup)
        # Run everything
        TAGS=""
        ;;
    --nfs-only)
        TAGS="--tags nfs"
        ;;
    --boot-only)
        TAGS="--tags tftp"
        ;;
    --tags)
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

echo "Running playbook: $PLAYBOOK $TAGS"
echo "Working directory: $SCRIPT_DIR/ansible"
echo ""

# Run Ansible in Docker
docker run --rm \
    -v "$SCRIPT_DIR:/workspace" \
    -v "$HOME/.ssh/raspberrypi_rsa:/root/.ssh/id_rsa:ro" \
    -w /workspace/ansible \
    cytopia/ansible:latest-tools \
    ansible-playbook -i inventory.yml "$PLAYBOOK" $TAGS $EXTRA_ARGS

echo ""
echo "Playbook completed successfully!"
