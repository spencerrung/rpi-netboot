#!/bin/bash
# SD Card Provisioning Script
# This script runs during network boot to provision the SD card with the OS
# Once complete, the Pi will reboot and boot from SD card

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SD_DEVICE="/dev/mmcblk0"
SD_BOOT_PART="${SD_DEVICE}p1"
SD_ROOT_PART="${SD_DEVICE}p2"
TEMP_MOUNT="/mnt/sd-provision"
NFS_ROOT_SOURCE="/"
PROVISION_MARKER="/boot/firmware/.sd-provisioned"

# Get Pi serial number
get_serial() {
    grep Serial /proc/cpuinfo | awk '{print substr($NF,9,8)}'
}

# Get hostname from serial number
get_hostname() {
    local serial=$(get_serial)
    case "$serial" in
        "94a418cd") echo "pi-01" ;;
        "54ab2151") echo "pi-02" ;;
        "101af127") echo "pi-03" ;;
        "c56a6028") echo "pi-04" ;;
        "ea4cc994") echo "pi-05" ;;
        *) echo "raspberrypi-${serial}" ;;
    esac
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if we're booted from NFS (provisioning mode)
check_boot_source() {
    local root_device=$(findmnt -n -o SOURCE /)
    if [[ ! "$root_device" =~ "nfs" ]] && [[ ! "$root_device" =~ ":" ]]; then
        log_info "Not booted from NFS. Already running from SD card."
        log_info "Current root: $root_device"
        exit 0
    fi
    log_info "Booted from NFS: $root_device"
}

# Check if SD card exists
check_sd_card() {
    if [ ! -b "$SD_DEVICE" ]; then
        log_warn "SD card not found at $SD_DEVICE"
        log_warn "Continuing network boot without provisioning"
        exit 0
    fi
    log_info "SD card found: $SD_DEVICE"
}

# Check if SD card is already provisioned
check_provisioned() {
    # Try to mount SD card boot partition and check for marker
    mkdir -p /tmp/sd-check
    if mount -o ro "${SD_BOOT_PART}" /tmp/sd-check 2>/dev/null; then
        if [ -f "/tmp/sd-check/.sd-provisioned" ]; then
            log_info "SD card already provisioned!"
            umount /tmp/sd-check
            rmdir /tmp/sd-check
            exit 0
        fi
        umount /tmp/sd-check
    fi
    rmdir /tmp/sd-check 2>/dev/null || true
}

# Partition the SD card
partition_sd() {
    log_step "Partitioning SD card..."

    # Unmount any existing partitions
    umount ${SD_DEVICE}* 2>/dev/null || true

    # Create partition table
    parted -s "$SD_DEVICE" mklabel msdos

    # Create boot partition (512MB, FAT32)
    parted -s "$SD_DEVICE" mkpart primary fat32 1MiB 513MiB
    parted -s "$SD_DEVICE" set 1 boot on

    # Create root partition (rest of disk, ext4)
    parted -s "$SD_DEVICE" mkpart primary ext4 513MiB 100%

    # Wait for kernel to update
    sleep 2
    partprobe "$SD_DEVICE"
    sleep 2

    log_info "Partitions created successfully"
}

# Format partitions
format_partitions() {
    log_step "Formatting boot partition (FAT32)..."
    mkfs.vfat -F 32 -n boot "$SD_BOOT_PART"

    log_step "Formatting root partition (ext4)..."
    mkfs.ext4 -F -L rootfs "$SD_ROOT_PART"

    log_info "Partitions formatted successfully"
}

# Copy root filesystem to SD card
copy_rootfs() {
    log_step "Mounting SD card root partition..."
    mkdir -p "$TEMP_MOUNT"
    mount "$SD_ROOT_PART" "$TEMP_MOUNT"

    log_step "Copying root filesystem to SD card..."
    log_info "This may take 5-10 minutes, please be patient..."

    # Copy everything except system directories and temporary files
    rsync -aAX --info=progress2 \
        --exclude='/dev/*' \
        --exclude='/proc/*' \
        --exclude='/sys/*' \
        --exclude='/tmp/*' \
        --exclude='/run/*' \
        --exclude='/mnt/*' \
        --exclude='/media/*' \
        --exclude='/lost+found' \
        --exclude="$TEMP_MOUNT" \
        "$NFS_ROOT_SOURCE" "$TEMP_MOUNT/" || true

    log_info "Root filesystem copied successfully"
}

# Copy boot files to SD card
copy_boot() {
    log_step "Creating boot mount point..."
    mkdir -p "$TEMP_MOUNT/boot/firmware"

    log_step "Mounting SD card boot partition..."
    mount "$SD_BOOT_PART" "$TEMP_MOUNT/boot/firmware"

    log_step "Copying boot files from /boot/firmware/ ..."

    # Verify source boot files exist
    if [ ! -f "/boot/firmware/start4.elf" ]; then
        log_error "Critical boot files missing in /boot/firmware/"
        log_error "Run: ansible-playbook rpi-netboot.yml to sync boot files"
        exit 1
    fi

    # Copy all boot files (FAT32 doesn't support ownership, so skip -a and use -rlptv)
    rsync -rlptv --info=progress2 --no-owner --no-group /boot/firmware/* "$TEMP_MOUNT/boot/firmware/" || {
        log_error "Failed to copy boot files"
        exit 1
    }

    # Verify critical boot files were copied
    for file in start4.elf fixup4.dat kernel8.img config.txt; do
        if [ ! -f "$TEMP_MOUNT/boot/firmware/$file" ]; then
            log_error "Missing critical boot file after copy: $file"
            exit 1
        fi
    done

    log_info "Boot files copied successfully"
    log_info "Verified: start4.elf, fixup4.dat, kernel8.img, config.txt"
}

# Configure SD card for local boot
configure_boot() {
    local hostname=$(get_hostname)
    local serial=$(get_serial)

    log_step "Configuring boot for SD card..."
    log_info "Hostname: $hostname"
    log_info "Serial: $serial"

    # Get root partition UUID
    local root_partuuid=$(blkid -s PARTUUID -o value "$SD_ROOT_PART")
    local boot_partuuid=$(blkid -s PARTUUID -o value "$SD_BOOT_PART")

    log_info "Root PARTUUID: $root_partuuid"
    log_info "Boot PARTUUID: $boot_partuuid"

    # Update cmdline.txt to boot from SD card
    cat > "$TEMP_MOUNT/boot/firmware/cmdline.txt" <<EOF
console=tty1 root=PARTUUID=${root_partuuid} rootfstype=ext4 fsck.repair=yes rootwait cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
EOF

    # Update fstab
    cat > "$TEMP_MOUNT/etc/fstab" <<EOF
proc            /proc           proc    defaults          0       0
PARTUUID=${root_partuuid}  /               ext4    defaults,noatime  0       1
PARTUUID=${boot_partuuid}  /boot/firmware  vfat    defaults          0       2
EOF

    # Set hostname
    echo "$hostname" > "$TEMP_MOUNT/etc/hostname"

    # Update /etc/hosts
    cat > "$TEMP_MOUNT/etc/hosts" <<EOF
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       ${hostname}
EOF

    # Remove the hostname service since we've set it statically
    rm -f "$TEMP_MOUNT/etc/systemd/system/set-hostname.service" 2>/dev/null || true
    rm -f "$TEMP_MOUNT/etc/systemd/system/sysinit.target.wants/set-hostname.service" 2>/dev/null || true
    rm -f "$TEMP_MOUNT/usr/local/bin/set-hostname-from-serial.sh" 2>/dev/null || true

    # Remove the SD provisioning service from the SD card (only needed on NFS boot)
    rm -f "$TEMP_MOUNT/etc/systemd/system/provision-sd-card.service" 2>/dev/null || true
    rm -f "$TEMP_MOUNT/etc/systemd/system/sysinit.target.wants/provision-sd-card.service" 2>/dev/null || true
    rm -f "$TEMP_MOUNT/usr/local/bin/provision-sd.sh" 2>/dev/null || true

    # Mark as provisioned
    touch "$TEMP_MOUNT/boot/firmware/.sd-provisioned"
    echo "Provisioned on $(date) for $hostname ($serial)" > "$TEMP_MOUNT/boot/firmware/.sd-provisioned"

    log_info "Boot configuration complete"
}

# Cleanup and unmount
cleanup() {
    log_step "Cleaning up..."

    umount "$TEMP_MOUNT/boot/firmware" 2>/dev/null || true
    umount "$TEMP_MOUNT" 2>/dev/null || true

    log_info "Cleanup complete"
}

# Main provisioning flow
main() {
    echo ""
    log_info "========================================="
    log_info "Raspberry Pi SD Card Provisioning"
    log_info "========================================="
    echo ""

    log_info "Pi Serial: $(get_serial)"
    log_info "Hostname: $(get_hostname)"
    echo ""

    check_boot_source
    check_sd_card
    check_provisioned

    log_warn "This will ERASE all data on $SD_DEVICE"
    log_info "Starting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5

    partition_sd
    format_partitions
    copy_rootfs
    copy_boot
    configure_boot
    cleanup

    echo ""
    log_info "========================================="
    log_info "Provisioning Complete!"
    log_info "========================================="
    echo ""
    log_info "The Pi will now reboot and boot from SD card"
    log_info "Hostname: $(get_hostname)"
    log_info "Serial: $(get_serial)"
    echo ""
    log_info "Rebooting in 10 seconds..."
    sleep 10

    reboot
}

# Run main function
main "$@"
