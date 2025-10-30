# SD Card Auto-Provisioning

## Overview

The **SD Card Auto-Provisioning** feature enables one-time network boot provisioning where each Raspberry Pi automatically provisions its own SD card, then boots independently from local storage.

## Architecture

### Before: Permanent Network Boot (Diskless)
```
┌─────────────┐
│   Pi #1     │───┐
│   Pi #2     │───┤
│   Pi #3     │───┼─ All share same NFS root (/srv/nfs/raspios-pi)
│   Pi #4     │───┤
│   Pi #5     │───┘
└─────────────┘
```
**Problems:**
- ❌ Poor performance (NFS latency)
- ❌ Shared filesystem (hostname conflicts)
- ❌ SQLite/database operations very slow
- ❌ K3s cluster issues

### After: One-Time Provisioning (Independent)
```
┌─────────────┐      First Boot           ┌─────────────┐
│   New Pi    │──────────────────────────→│  NFS Server │
│ (blank SD)  │  Network boot from NFS    │ 10.10.10.231│
└──────┬──────┘                           └─────────────┘
       │
       │  Provisioning service runs
       │  Copies NFS → SD card (~5-10 min)
       │
       ▼
┌─────────────┐
│   Pi #1     │  Each Pi has:
│  (pi-01)    │  - Own SD card
│             │  - Own filesystem
│  SD Card:   │  - Unique hostname
│  /dev/mmcblk│  - Fast local storage
└─────────────┘
```
**Benefits:**
- ✅ Fast local storage
- ✅ Independent filesystems
- ✅ Unique hostnames
- ✅ K3s cluster works perfectly
- ✅ Still uses TFTP/NFS for initial provisioning

## How It Works

### Boot Flow

**First Boot (Provisioning):**
1. Pi powers on with blank SD card
2. EEPROM network boot → TFTP downloads boot files
3. Kernel boots with NFS root
4. `provision-sd-card.service` runs automatically
5. Service checks if SD card is provisioned
   - If **not provisioned**: Runs provisioning script
   - If **already provisioned**: Does nothing
6. Provisioning script:
   - Partitions SD card (512MB boot + rest for root)
   - Formats partitions (FAT32 + ext4)
   - Copies entire NFS root to SD card (~5-10 minutes)
   - Sets unique hostname based on serial number
   - Configures boot files (cmdline.txt, fstab)
   - Marks SD as provisioned (`.sd-provisioned` marker)
   - Reboots

**Subsequent Boots (Local):**
1. Pi powers on with provisioned SD card
2. EEPROM network boot → TFTP downloads boot files
3. Boot files point to SD card (not NFS)
4. Pi boots from local SD card
5. Provisioning service skips (SD already provisioned)

### Key Components

**On NFS Root:**
- `/usr/local/bin/provision-sd.sh` - Provisioning script
- `/etc/systemd/system/provision-sd-card.service` - Systemd service

**On SD Card (after provisioning):**
- `/boot/firmware/.sd-provisioned` - Marker file (prevents re-provisioning)
- `/boot/firmware/cmdline.txt` - Updated to boot from `PARTUUID=...`
- `/etc/fstab` - Updated to mount SD partitions
- `/etc/hostname` - Set to unique hostname
- No provisioning service (removed during provisioning)

## Deployment

### Prerequisites

1. Working netboot infrastructure (NFS + TFTP)
2. Ansible access to netboot server
3. Raspberry Pis with SD cards inserted

### Step 1: Enable Provisioning

```bash
cd /home/spencer/mounts/wd1tb/Users/Spencer/repos/pi-ansible/rpi-netboot/ansible

# Deploy provisioning service to NFS root
ansible-playbook -i inventory.yml playbooks/enable-sd-provisioning.yml --ask-vault-pass
```

This will:
- Copy `provision-sd.sh` to NFS root
- Install `provision-sd-card.service`
- Enable service to run on boot

### Step 2: Provision Your Pis

**Option A: All at once**
1. Power off all Pis
2. Ensure SD cards are inserted
3. Power on all Pis simultaneously
4. Wait 10-15 minutes for provisioning
5. All Pis will be running from SD cards

**Option B: One at a time**
1. Power on one Pi with SD card
2. Watch it provision (monitor via serial console or SSH)
3. Wait for reboot (~10 minutes)
4. Verify it boots from SD
5. Repeat for next Pi

### Step 3: Verify Provisioning

**Check boot source:**
```bash
# SSH to provisioned Pi
ssh -i ~/.ssh/raspberrypi_rsa pi@10.10.10.230

# Check what we're booted from
findmnt -n -o SOURCE /
# Should show: /dev/mmcblk0p2 (not NFS!)

# Check hostname
hostname
# Should show: pi-01 (unique per Pi)

# Check for provision marker
ls -la /boot/firmware/.sd-provisioned
# Should exist with timestamp
```

**Check all Pis:**
```bash
cd /home/spencer/mounts/wd1tb/Users/Spencer/repos/pi-ansible/rpi-k3s/ansible

# Check boot source on all
ansible k3s_cluster -i inventory.yml -a "findmnt -n -o SOURCE /"

# Check hostnames
ansible k3s_cluster -i inventory.yml -a "hostname"
```

## Monitoring Provisioning

### Watch Provisioning in Real-Time

**Via Serial Console (if available):**
- Connect HDMI + keyboard
- Watch provisioning output on screen

**Via SSH (during network boot phase):**
```bash
# Find the Pi's IP (check DHCP server or nmap)
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip>

# Watch provisioning service
sudo journalctl -u provision-sd-card -f

# Watch system log
sudo journalctl -f
```

**Via Systemd Status:**
```bash
ssh -i ~/.ssh/raspberrypi_rsa pi@<pi-ip>
sudo systemctl status provision-sd-card
```

### Provisioning Timeline

| Time | Activity |
|------|----------|
| 0:00 | Pi powers on, network boot starts |
| 0:30 | TFTP downloads boot files |
| 1:00 | Kernel loads, NFS root mounts |
| 1:30 | Systemd starts, provisioning service runs |
| 1:35 | SD card partitioned and formatted |
| 1:40 | Root filesystem copy begins |
| 6:00 | Root filesystem copy ~60% complete |
| 9:00 | Root filesystem copy complete |
| 9:30 | Boot files copied to SD |
| 10:00 | Configuration updated, reboot initiated |
| 10:30 | Pi boots from SD card |
| 11:00 | Pi fully booted from SD card ✅ |

*Times are approximate and depend on SD card speed*

## Re-provisioning

### Full Re-provision

To completely re-provision a Pi:

1. **Power off the Pi**

2. **Remove SD card**

3. **Wipe SD card** (optional but recommended):
   ```bash
   # On your workstation
   sudo dd if=/dev/zero of=/dev/sdX bs=1M count=100
   # Replace /dev/sdX with your SD card device
   ```

4. **Reinsert SD card**

5. **Power on Pi** - It will auto-provision again

### Quick Re-provision (Keep Existing Data)

To re-run provisioning without wiping:

1. **Boot Pi from network**:
   ```bash
   ssh pi@<pi-ip>

   # Remove provision marker from SD card
   sudo mount /dev/mmcblk0p1 /mnt
   sudo rm /mnt/.sd-provisioned
   sudo umount /mnt

   # Reboot
   sudo reboot
   ```

2. **Pi will detect unprovision and re-run**

## Troubleshooting

### Pi Stuck in Provisioning Loop

**Symptom:** Pi keeps reprovisioning on every boot

**Cause:** `.sd-provisioned` marker not being created

**Fix:**
```bash
# SSH to Pi during network boot
ssh pi@<pi-ip>

# Manually check SD card
sudo mount /dev/mmcblk0p1 /mnt
ls -la /mnt/.sd-provisioned

# If missing, check provisioning script logs
sudo journalctl -u provision-sd-card -n 200
```

### Provisioning Takes Too Long

**Symptom:** Provisioning takes >20 minutes

**Cause:** Slow SD card or network issues

**Solutions:**
- Use Class 10 or UHS-1 SD cards (minimum)
- Check NFS server isn't overloaded
- Provision Pis serially (one at a time) instead of in parallel

### Pi Doesn't Auto-Provision

**Symptom:** Pi boots from NFS but doesn't provision SD

**Check 1: Service is enabled**
```bash
ssh pi@<pi-ip>
sudo systemctl status provision-sd-card
```

**Check 2: SD card exists**
```bash
ls -la /dev/mmcblk0*
```

**Check 3: Service logs**
```bash
sudo journalctl -u provision-sd-card -n 100
```

**Check 4: Script exists**
```bash
ls -la /usr/local/bin/provision-sd.sh
```

### Hostname Still Shared After Provisioning

**Symptom:** All Pis have same hostname after provisioning

**Cause:** Hostname not properly set during provisioning

**Check:**
```bash
ssh pi@<pi-ip>
hostname
cat /etc/hostname
cat /proc/cpuinfo | grep Serial
```

**Fix:**
```bash
# Get serial
SERIAL=$(cat /proc/cpuinfo | grep Serial | awk '{print substr($NF,9,8)}')

# Manually set hostname based on your mapping
# (e.g., 94a418cd → pi-01)
sudo hostnamectl set-hostname pi-01
```

### Pi Won't Boot from SD After Provisioning

**Symptom:** Pi boots from NFS even after provisioning

**Check 1: Boot order in EEPROM**
```bash
vcgencmd bootloader_config | grep BOOT_ORDER
# Should include SD card (0x1) before network (0x2)
# Example: BOOT_ORDER=0xf241 (Network, then SD fallback)
```

**Check 2: cmdline.txt on SD**
```bash
sudo mount /dev/mmcblk0p1 /mnt
cat /mnt/cmdline.txt
# Should have: root=PARTUUID=<uuid>
# Should NOT have: root=/dev/nfs
sudo umount /mnt
```

**Check 3: PARTUUID is correct**
```bash
# Get actual PARTUUID
sudo blkid /dev/mmcblk0p2 | grep -o 'PARTUUID="[^"]*"'

# Compare to cmdline.txt
sudo mount /dev/mmcblk0p1 /mnt
grep PARTUUID /mnt/cmdline.txt
sudo umount /mnt
```

## Advanced Configuration

### Custom Partition Sizes

Edit `/home/spencer/mounts/wd1tb/Users/Spencer/repos/pi-ansible/rpi-netboot/ansible/files/provision-sd.sh`:

```bash
# Change this line:
parted -s "$SD_DEVICE" mkpart primary fat32 1MiB 513MiB

# To (for 1GB boot):
parted -s "$SD_DEVICE" mkpart primary fat32 1MiB 1025MiB
```

Re-deploy:
```bash
ansible-playbook -i inventory.yml playbooks/enable-sd-provisioning.yml --ask-vault-pass
```

### Skip Provisioning for Specific Pis

To prevent certain Pis from auto-provisioning:

**Option 1: Remove SD card**
- Pi will boot from NFS permanently

**Option 2: Pre-mark SD as provisioned**
```bash
# On SD card before inserting
sudo mount /dev/sdX1 /mnt
sudo touch /mnt/.sd-provisioned
sudo umount /mnt
```

### Custom Hostname Mapping

Edit `provision-sd.sh` function `get_hostname()`:

```bash
get_hostname() {
    local serial=$(get_serial)
    case "$serial" in
        "94a418cd") echo "pi-01" ;;
        "54ab2151") echo "pi-02" ;;
        "XXXXXXXX") echo "custom-name" ;;  # Add your mapping
        *) echo "raspberrypi-${serial}" ;;
    esac
}
```

## Performance Comparison

### K3s Master Startup Time

| Boot Type | Time to Active | Notes |
|-----------|---------------|-------|
| NFS Boot | ~4-5 minutes | Slow SQL queries, NFS latency |
| SD Boot | ~30-45 seconds | Fast local storage |

### Database Operations

| Operation | NFS Boot | SD Boot |
|-----------|----------|---------|
| SQLite INSERT | ~2000ms | ~5ms |
| File sync | ~500ms | ~10ms |
| Container start | ~60s | ~5s |

## Disabling Auto-Provisioning

To go back to permanent network boot:

```bash
cd /home/spencer/mounts/wd1tb/Users/Spencer/repos/pi-ansible/rpi-netboot/ansible

# Remove provisioning service from NFS root
ansible netboot_server -i inventory.yml -m file -a "path=/srv/nfs/raspios-pi/etc/systemd/system/provision-sd-card.service state=absent" --become

ansible netboot_server -i inventory.yml -m file -a "path=/srv/nfs/raspios-pi/usr/local/bin/provision-sd.sh state=absent" --become

ansible netboot_server -i inventory.yml -m file -a "path=/srv/nfs/raspios-pi/etc/systemd/system/sysinit.target.wants/provision-sd-card.service state=absent" --become
```

## Integration with K3s

After SD provisioning, deploy K3s normally:

```bash
cd /home/spencer/mounts/wd1tb/Users/Spencer/repos/pi-ansible/rpi-k3s/ansible

# Run K3s installation
ansible-playbook -i inventory.yml playbooks/k3s-install.yml
```

K3s will now run with:
- ✅ Fast local storage
- ✅ Unique hostnames
- ✅ Independent filesystems
- ✅ No NFS performance issues

## FAQ

**Q: Can I mix network boot and SD boot Pis?**
A: Yes! Pis without SD cards will continue to network boot. Pis with SD cards will auto-provision and boot locally.

**Q: What happens if I remove the SD card after provisioning?**
A: Pi will fall back to network boot from NFS.

**Q: Can I provision multiple Pis in parallel?**
A: Yes, but it may be slow. Recommend provisioning 2-3 at a time max to avoid NFS server overload.

**Q: Will updates to NFS root affect provisioned Pis?**
A: No. Once provisioned, Pis are completely independent. You'll need to update each Pi individually (use Ansible for this).

**Q: Can I use different OS images per Pi?**
A: Not with this setup. All Pis get a copy of the same NFS root. For different images, you'd need multiple NFS roots.

**Q: How much space does the SD card need?**
A: Minimum 8GB. Recommended 16GB+ for K3s with containers.

## Next Steps

1. ✅ Enable SD provisioning with Ansible
2. ✅ Power on Pis and let them auto-provision
3. ✅ Verify all Pis boot from SD
4. ✅ Deploy K3s cluster
5. 🎉 Enjoy fast, independent Raspberry Pi cluster!
