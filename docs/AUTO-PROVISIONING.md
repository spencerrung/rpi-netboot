# Auto-Provisioning Service

## Overview

The **Pi Auto-Provisioning Service** automatically provisions new Raspberry Pis as they attempt to network boot - **no manual configuration required!**

## How It Works

```
┌─────────────┐
│  New Pi     │  1. Attempts network boot with serial XXXXXXXX
│  (blank SD) │     Requests: /opt/netboot/config/menus/XXXXXXXX/...
└──────┬──────┘
       │
       │ 2. TFTP server logs the request
       ▼
┌─────────────┐
│  dnsmasq    │  3. Logs show: "TFTP sent /XXXXXXXX/start4.elf"
│  (TFTP)     │
└──────┬──────┘
       │
       │ 4. Auto-provision service monitors logs
       ▼
┌─────────────┐
│ auto-       │  5. Detects new serial XXXXXXXX
│ provision   │  6. Creates /opt/netboot/config/menus/XXXXXXXX/
│ service     │  7. Copies boot files from template
└──────┬──────┘
       │
       │ 8. Pi retries boot request
       ▼
┌─────────────┐
│  New Pi     │  9. Files now exist - Pi boots successfully! ✅
│  (booting)  │
└─────────────┘
```

## Key Features

- ✅ **Zero-touch provisioning** - No manual serial collection
- ✅ **Real-time monitoring** - Provisions within seconds
- ✅ **Template-based** - All Pis get identical boot config
- ✅ **Automatic** - Runs as systemd service
- ✅ **Scalable** - Handle hundreds of Pis

## Architecture Shift

### Old Way (Static)
```yaml
# ansible/group_vars/all.yml
raspberry_pis:
  - serial: "94a418cd"  # ❌ Manual entry required
    hostname: "pi-01"
  - serial: "XXXXXXXX"  # ❌ Must know serial ahead of time
    hostname: "pi-02"
```
**Problem:** Must collect serials manually, update config, run Ansible

### New Way (Dynamic)
```bash
# Just power on any Pi - it auto-provisions!
# No configuration needed! ✅
```
**Benefit:** Truly zero-touch - any Pi boots automatically

## Deployment

### 1. Deploy Auto-Provision Service

```bash
cd rpi-netboot

# Deploy the service
./run-playbook.sh ansible/deploy-auto-provision.yml
```

This will:
- Copy auto-provision script to `/usr/local/bin/`
- Install systemd service
- Create template from existing Pi (94a418cd)
- Start monitoring service

### 2. Verify Service Running

```bash
ssh pi@10.10.10.231
sudo systemctl status pi-auto-provision
```

Expected output:
```
● pi-auto-provision.service - Raspberry Pi Auto-Provisioning Service
   Active: active (running) since ...
```

### 3. Monitor Logs

```bash
# Real-time service logs
sudo journalctl -u pi-auto-provision -f

# Or check the log file
tail -f /var/log/pi-auto-provision.log
```

## Testing

### Test 1: Provision a New Pi

1. **Power on a new Pi** with blank SD card
2. **Watch the logs**:
   ```bash
   ssh pi@10.10.10.231
   tail -f /var/log/pi-auto-provision.log
   ```

3. **Expected output**:
   ```
   [2025-10-11 18:00:00] 🆕 NEW PI DETECTED: 12345678
   [2025-10-11 18:00:00] 📁 Creating boot directory: /opt/netboot/config/menus/12345678
   [2025-10-11 18:00:00] 📋 Copying boot files from template...
   [2025-10-11 18:00:01] ✅ Pi 12345678 provisioned successfully!
   ```

4. **Verify directory created**:
   ```bash
   ls -la /opt/netboot/config/menus/12345678/
   ```

### Test 2: Verify Pi Boots

After auto-provisioning:
1. Pi will retry boot request
2. Files now exist
3. Pi boots successfully
4. Check it comes online:
   ```bash
   # Wait ~60 seconds, then
   nmap -sn 192.168.1.0/24  # Scan for new Pi
   ```

## Template Management

### What is the Template?

The **template directory** (`/opt/netboot/config/menus/template/`) contains the master copy of boot files that get copied to each new Pi.

### Template Contents

```
template/
├── start4.elf
├── fixup4.dat
├── bootcode.bin
├── bcm2711-rpi-4-b.dtb
├── kernel8.img
├── initrd.img
├── config.txt      ← Boot configuration
├── cmdline.txt     ← Kernel parameters
└── overlays/       ← Device tree overlays
```

### Update Template (Update All Future Pis)

To change the configuration for all **future** Pis:

```bash
ssh pi@10.10.10.231

# Edit template config
sudo vim /opt/netboot/config/menus/template/config.txt

# Or update from Ansible
cd rpi-netboot
# Edit ansible/templates/config.txt.j2
./run-playbook.sh --boot-only  # This updates template too
```

**Note:** This only affects NEW Pis. Existing Pis keep their current config.

### Update Existing Pis

To update already-provisioned Pis, run the Ansible playbook:

```bash
# This updates all Pi directories including template
./run-playbook.sh --boot-only
```

## Monitoring & Operations

### Check Service Status

```bash
sudo systemctl status pi-auto-provision
```

### View Real-time Logs

```bash
sudo journalctl -u pi-auto-provision -f
```

### Restart Service

```bash
sudo systemctl restart pi-auto-provision
```

### Stop Service

```bash
sudo systemctl stop pi-auto-provision
```

### View Provisioned Pis

```bash
ls -1 /opt/netboot/config/menus/ | grep -E '^[0-9a-f]{8}$'
```

### Count Provisioned Pis

```bash
ls -1d /opt/netboot/config/menus/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] | wc -l
```

## Troubleshooting

### Service Not Starting

```bash
# Check service status
sudo systemctl status pi-auto-provision

# Check logs
sudo journalctl -u pi-auto-provision -n 50

# Verify script exists and is executable
ls -la /usr/local/bin/auto-provision-pi.sh
```

### Template Missing

If template doesn't exist, service will try to create it from first Pi directory.

**Manually create template:**
```bash
# Copy from existing Pi
sudo cp -r /opt/netboot/config/menus/94a418cd /opt/netboot/config/menus/template
sudo chown -R pi:pi /opt/netboot/config/menus/template
```

### Pi Not Auto-Provisioning

1. **Check service is running:**
   ```bash
   sudo systemctl status pi-auto-provision
   ```

2. **Check dnsmasq is logging:**
   ```bash
   sudo journalctl -u '*dnsmasq*' | grep TFTP | tail -20
   ```

3. **Verify Pi is requesting files:**
   ```bash
   # Watch TFTP requests in real-time
   sudo journalctl -u '*dnsmasq*' -f | grep TFTP
   ```

4. **Check permissions:**
   ```bash
   ls -la /opt/netboot/config/menus/
   # Should be owned by pi:pi
   ```

### Manual Provision a Serial

If auto-provision isn't working, manually provision:

```bash
SERIAL="12345678"
sudo cp -r /opt/netboot/config/menus/template /opt/netboot/config/menus/$SERIAL
sudo chown -R pi:pi /opt/netboot/config/menus/$SERIAL
```

## Integration with Ansible

### Hybrid Approach (Recommended)

Use **both** auto-provisioning and Ansible:

1. **Auto-provision** handles initial deployment (fast, automatic)
2. **Ansible** handles configuration management (updates, changes)

**Workflow:**
```
New Pi boots → Auto-provisioned with template
              ↓
         (Pi boots successfully)
              ↓
  Ansible updates config as needed (optional)
```

### Disable Auto-Provisioning

If you want to go back to manual Ansible-only approach:

```bash
ssh pi@10.10.10.231
sudo systemctl stop pi-auto-provision
sudo systemctl disable pi-auto-provision
```

## Advanced Configuration

### Change Check Interval

Edit the service:
```bash
sudo vim /usr/local/bin/auto-provision-pi.sh
# Change: CHECK_INTERVAL=5  # seconds
```

Restart service:
```bash
sudo systemctl restart pi-auto-provision
```

### Add Notification Webhook

Edit script to call webhook when new Pi provisioned:

```bash
sudo vim /usr/local/bin/auto-provision-pi.sh

# Add to provision_serial() function:
notify_new_pi() {
    local serial="$1"
    curl -X POST https://your-webhook.com/new-pi \
         -H "Content-Type: application/json" \
         -d "{\"serial\": \"$serial\", \"time\": \"$(date)\"}"
}
```

### Custom Template per Serial Pattern

Modify script to use different templates based on serial prefix:

```bash
# Example: First 2 chars of serial determine template
TEMPLATE_DIR="${TFTP_ROOT}/template-${serial:0:2}"
```

## Security Considerations

- ✅ Service runs as root (required for file creation)
- ✅ SystemD hardening applied (PrivateTmp, ProtectSystem)
- ✅ Only writes to TFTP directory
- ⚠️ Any Pi can self-provision (by design)
- 💡 Consider network segmentation for production

## Performance

- **Check interval:** 5 seconds (configurable)
- **Provision time:** ~1-2 seconds per Pi
- **Log parsing:** Minimal CPU usage
- **Scalability:** Can handle 100+ Pis easily

## Comparison: Static vs Dynamic

| Aspect | Static (Ansible) | Dynamic (Auto-Provision) |
|--------|------------------|--------------------------|
| Manual serial collection | ❌ Required | ✅ Not needed |
| Time to provision | ~5-10 min | ~5-10 seconds |
| Configuration management | ✅ Full control | ⚠️ Template-based |
| Scalability | 😐 Moderate | ✅ Excellent |
| Per-Pi customization | ✅ Easy | ❌ Requires Ansible |
| Zero-touch | ❌ No | ✅ Yes |

## Recommendation

**Use BOTH:**
1. **Auto-provision** for initial deployment (speed)
2. **Ansible** for configuration management (control)

This gives you the best of both worlds!

## Next Steps

1. ✅ Deploy auto-provision service
2. ✅ Test with a new Pi
3. ✅ Monitor logs to verify
4. ⏭️ Scale to many Pis!
