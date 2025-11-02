#!/bin/bash
# Auto-Provision Raspberry Pi Network Boot
# Monitors TFTP requests and automatically provisions new Pis

set -euo pipefail

# Configuration
TFTP_ROOT="/opt/netboot/config/menus"
TEMPLATE_DIR="${TFTP_ROOT}/template"
LOG_FILE="/var/log/pi-auto-provision.log"
CHECK_INTERVAL=5  # seconds

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to check if serial directory exists
serial_exists() {
    local serial="$1"
    [[ -d "${TFTP_ROOT}/${serial}" ]]
}

# Function to provision a new Pi serial
provision_serial() {
    local serial="$1"

    log "🆕 NEW PI DETECTED: ${serial}"
    log "📁 Creating boot directory: ${TFTP_ROOT}/${serial}"

    # Create serial directory
    mkdir -p "${TFTP_ROOT}/${serial}"

    # Copy all files from template
    log "📋 Copying boot files from template..."
    cp -r "${TEMPLATE_DIR}"/* "${TFTP_ROOT}/${serial}/"

    # Set correct permissions (tftpd-hpa runs as tftp user)
    chown -R tftp:tftp "${TFTP_ROOT}/${serial}"
    chmod 755 "${TFTP_ROOT}/${serial}"
    find "${TFTP_ROOT}/${serial}" -type f -exec chmod 644 {} \;

    log "✅ Pi ${serial} provisioned successfully!"
    log "   Path: ${TFTP_ROOT}/${serial}"

    # Optional: Send notification (webhook, email, etc)
    # notify_new_pi "${serial}"
}

# Function to extract serials from tftpd-hpa syslog
get_attempted_serials() {
    # Parse syslog for TFTP requests with serial patterns
    # tftpd-hpa verbose logs: "RRQ from 10.10.10.122 filename e2c042ff/start4.elf"
    # or old format: "file /opt/netboot/config/menus/54ab2151/start4.elf not found"
    journalctl --since "$((CHECK_INTERVAL + 2)) seconds ago" -u tftpd-hpa 2>/dev/null \
        | grep -oP '(?:filename\s+|'"${TFTP_ROOT}"'/)\K[0-9a-f]{8}(?=/)' \
        | sort -u
}

# Function to create template directory if it doesn't exist
ensure_template_exists() {
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        log "⚠️  Template directory not found: ${TEMPLATE_DIR}"
        log "Creating template from first existing Pi directory..."

        # Find first existing Pi directory
        local first_pi=$(find "$TFTP_ROOT" -maxdepth 1 -type d -name '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]' | head -1)

        if [[ -n "$first_pi" ]]; then
            log "📋 Using $(basename "$first_pi") as template"
            cp -r "$first_pi" "$TEMPLATE_DIR"
            chown -R tftp:tftp "$TEMPLATE_DIR"
            log "✅ Template created"
        else
            log "❌ ERROR: No existing Pi directories found to use as template!"
            log "   Please run Ansible playbook first to create initial boot files"
            exit 1
        fi
    fi
}

# Main monitoring loop
main() {
    log "🚀 Pi Auto-Provisioning Service Started"
    log "📂 TFTP Root: ${TFTP_ROOT}"
    log "📋 Template: ${TEMPLATE_DIR}"
    log "⏱️  Check Interval: ${CHECK_INTERVAL}s"
    log "🔍 Monitoring: journalctl -u tftpd-hpa"
    log ""

    # Ensure template directory exists
    ensure_template_exists

    # Track serials we've already provisioned this session
    declare -A provisioned_serials

    while true; do
        # Get serials that have attempted to boot
        while IFS= read -r serial; do
            # Skip if empty
            [[ -z "$serial" ]] && continue

            # Skip if already provisioned in this session
            [[ -n "${provisioned_serials[$serial]:-}" ]] && continue

            # Check if serial directory exists
            if ! serial_exists "$serial"; then
                provision_serial "$serial"
                provisioned_serials[$serial]=1
            fi
        done < <(get_attempted_serials)

        # Wait before next check
        sleep "$CHECK_INTERVAL"
    done
}

# Handle termination gracefully
trap 'log "🛑 Auto-Provisioning Service Stopped"; exit 0' SIGTERM SIGINT

# Run main loop
main
