# Tailscale Funnel Setup Guide for Pi-hole TRMNL Monitor

This guide explains how Tailscale Funnel is used in the Pi-hole TRMNL Monitor installation to provide secure, public HTTPS access to your Pi-hole statistics.

## What is Tailscale Funnel?

**Tailscale Funnel** is a feature that allows you to expose a local service to the public internet via HTTPS, without:
- Port forwarding on your router
- Exposing your home IP address
- Manual SSL certificate management
- Complex reverse proxy setups

### How It Works

```
TRMNL Server (anywhere on internet)
         ↓
    HTTPS request to https://your-device.ts.net/stats
         ↓
Tailscale Funnel (public HTTPS endpoint)
         ↓
   Tailscale Infrastructure (encrypted relay)
         ↓
   Your Pi-hole Device (Flask server on port 8080)
         ↓
    Pi-hole API
```

**Key Benefits:**
- ✅ **Automatic HTTPS**: Tailscale handles TLS certificates
- ✅ **Public Access**: Anyone with the URL can reach it (token-protected)
- ✅ **Privacy**: Your home IP stays hidden
- ✅ **Encryption**: End-to-end encryption for all traffic
- ✅ **No Configuration**: No router changes needed

## Requirements for Funnel

1. **Tailscale Account**: Free for personal use
2. **MagicDNS Enabled**: Automatically enabled for new accounts
3. **Tailscale v1.38.3+**: Installed by the setup script
4. **Supported Device**: Pi-hole running on Linux (Raspberry Pi, VM, etc.)

## How the Installer Configures Funnel

The `install.sh` script automatically:

### 1. Installs Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 2. Authenticates Your Device

```bash
sudo tailscale up
```

Opens a browser window for you to log in with:
- Google
- Microsoft
- GitHub
- Email

### 3. Enables Funnel

```bash
sudo tailscale funnel --bg --https=443 8080
```

This creates a public HTTPS endpoint that forwards to your Flask server on port 8080.

### 4. Configures systemd Service

The service file ensures Funnel is always running:

```ini
[Service]
# Wait for Tailscale to be fully connected
ExecStartPre=/bin/sleep 5
ExecStartPre=/usr/bin/tailscale status --wait

# Enable Funnel before starting Flask
ExecStartPre=/usr/bin/tailscale funnel --bg --https=443 8080

# Start Flask server
ExecStart=/opt/pihole-trmnl/venv/bin/python3 /opt/pihole-trmnl/pihole_api_server.py
```

**Result**: Every time the service starts (boot, restart, crash recovery), Funnel is re-enabled automatically.

## Verifying Funnel Status

### Check If Funnel Is Running

```bash
sudo tailscale funnel status
```

**Expected output:**
```
# Funnel on:
#     - https://your-device.tail1234.ts.net
#
#  Serve configuration:
#  |-- /
#      |-- proxy http://127.0.0.1:8080
```

### Check Tailscale Connection

```bash
tailscale status
```

**Look for:**
- Your device in the list
- Status: "active" or "connected"
- Your Tailscale hostname (e.g., `your-device.tail1234.ts.net`)

### Get Your Public URL

```bash
# Get hostname
tailscale status --json | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4

# Result: your-device.tail1234.ts.net
```

Your public URL will be: `https://your-device.tail1234.ts.net/stats?token=YOUR_TOKEN`

## Testing Funnel

### Test from Pi-hole Device

```bash
# Test local HTTP (bypasses Funnel)
curl "http://localhost:8080/health"

# Test public HTTPS (uses Funnel)
curl "https://$(tailscale status --json | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')/health"
```

Both should return JSON with `"status": "healthy"`.

### Test from Another Device

From your phone, laptop, or any internet-connected device:

```bash
curl "https://your-device.tail1234.ts.net/health"
```

No Tailscale required on the testing device - it's publicly accessible!

## Funnel Persistence

### Auto-Start on Boot

The systemd service ensures Funnel starts automatically:

```bash
# Check if enabled
sudo systemctl is-enabled pihole-trmnl-api.service

# Should output: enabled
```

### After Reboot

1. System boots
2. Tailscale daemon starts (`tailscaled.service`)
3. Pi-hole TRMNL service starts (`pihole-trmnl-api.service`)
4. Service waits for Tailscale to connect
5. Service enables Funnel
6. Flask server starts

**No manual intervention required!**

## Troubleshooting Funnel

### Funnel Won't Enable

**Error:** `"funnel not available"`

**Causes:**
1. MagicDNS not enabled
2. Tailscale plan doesn't support Funnel (unlikely - free plans support it)
3. Tailscale version too old

**Solutions:**

```bash
# Check MagicDNS status
tailscale status | grep "MagicDNS"

# Enable MagicDNS (if not enabled)
# Go to: https://login.tailscale.com/admin/dns
# Toggle "MagicDNS" to ON

# Update Tailscale
sudo apt update && sudo apt upgrade tailscale

# Retry Funnel
sudo tailscale funnel --bg --https=443 8080
```

### Funnel Stops After Reboot

**Check service status:**

```bash
sudo systemctl status pihole-trmnl-api.service
```

**Look for errors in logs:**

```bash
sudo journalctl -u pihole-trmnl-api.service -n 50
```

**Common issue:** ExecStartPre timing out. Fix:

```bash
# Edit service file
sudo nano /etc/systemd/system/pihole-trmnl-api.service

# Increase sleep time:
# ExecStartPre=/bin/sleep 10

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service
```

### HTTPS Endpoint Returns 404

**Cause:** Funnel is running but not configured correctly.

**Solution:**

```bash
# Disable Funnel
sudo tailscale funnel --https=443 off

# Wait 5 seconds
sleep 5

# Re-enable Funnel
sudo tailscale funnel --bg --https=443 8080

# Verify
sudo tailscale funnel status
```

### Certificate Errors

Tailscale manages certificates automatically. If you see certificate errors:

```bash
# Check Tailscale is up-to-date
sudo apt update && sudo apt upgrade tailscale

# Restart Tailscale daemon
sudo systemctl restart tailscaled

# Restart service
sudo systemctl restart pihole-trmnl-api.service
```

## Security Considerations

### What's Exposed

**Publicly accessible:**
- HTTPS endpoint: `https://your-device.ts.net`
- Requires API token for all data endpoints

**Not accessible without token:**
- Pi-hole statistics
- System information

**The token:**
- 256-bit random hex string (64 characters)
- Practically impossible to guess (2^256 combinations)
- Transmitted over HTTPS (encrypted)

### Who Can Access?

**Anyone with the full URL** (including token) can access your Pi-hole stats.

**Example:**
```
https://your-device.ts.net/stats?token=abc123...xyz789
```

If someone has this URL, they can see:
- Total DNS queries
- Blocked query count
- Active clients
- System CPU/RAM usage

They **cannot** see:
- Specific domains you visit
- Client IP addresses
- Ability to change Pi-hole settings

### Token Security

**Protect your token:**
- ❌ Don't share the URL publicly
- ❌ Don't commit it to GitHub/GitLab
- ✅ Store it securely in TRMNL plugin settings
- ✅ Regenerate if you suspect it's compromised

## Token Rotation

### Automated Token Rotation (Recommended)

The installation includes a dedicated rotation script that handles everything safely:

```bash
# Run the rotation script
sudo /opt/pihole-trmnl/rotate-token.sh
```

**What the script does:**
1. ✅ Backs up current token (for rollback)
2. ✅ Generates new cryptographically secure token
3. ✅ Updates systemd service file
4. ✅ Restarts service with new token
5. ✅ Tests new token works correctly
6. ✅ Automatically rolls back on any failure
7. ✅ Displays new TRMNL polling URLs

**Example output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  New TRMNL Polling URLs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Pi-hole Stats:
  https://your-hostname.ts.net/stats?token=abc123...xyz789

  System Info:
  https://your-hostname.ts.net/info/system?token=abc123...xyz789

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  IMPORTANT: Update Your TRMNL Plugin Configuration
```

**After rotation:**
1. Copy the new URLs
2. Log into https://usetrmnl.com/plugins
3. Edit your Pi-hole plugin
4. Replace BOTH polling URLs
5. Save changes

The old token is immediately invalidated and will no longer work.

### Manual Token Rotation

If you prefer manual control:

```bash
# 1. Generate new token
NEW_TOKEN=$(openssl rand -hex 32)

# 2. Update service file
sudo sed -i "s/API_TOKEN=.*/API_TOKEN=$NEW_TOKEN/" /etc/systemd/system/pihole-trmnl-api.service

# 3. Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service

# 4. Display new URLs
HOSTNAME=$(tailscale status --json | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')
echo "https://$HOSTNAME/stats?token=$NEW_TOKEN"
echo "https://$HOSTNAME/info/system?token=$NEW_TOKEN"

# 5. Update TRMNL plugin with new URLs
```

### Scheduling Automatic Rotation (Advanced)

**⚠️ Warning:** Automatic rotation will break TRMNL polling until you manually update the plugin URLs. Only use this if you have a way to update TRMNL programmatically.

To schedule rotation every 6 months via cron:

```bash
# Edit root's crontab
sudo crontab -e

# Add this line (runs at midnight on 1st of January and July)
0 0 1 1,7 * /opt/pihole-trmnl/rotate-token.sh > /var/log/pihole-trmnl-rotation.log 2>&1

# Save and exit
```

**Recommendation:** Manual rotation is better for most users. The rotation script makes it quick and easy.

### Optional Firewall Hardening

Block local network access to force HTTPS-only:

```bash
# Install UFW (if not installed)
sudo apt install ufw

# Allow SSH (important!)
sudo ufw allow 22/tcp

# Allow Pi-hole ports
sudo ufw allow 80/tcp
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Allow from Tailscale subnet to port 8080
sudo ufw allow from 100.64.0.0/10 to any port 8080

# Allow from localhost
sudo ufw allow from 127.0.0.1 to any port 8080

# Deny all other access to port 8080
sudo ufw deny 8080

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status numbered
```

**Effect:** Local network users cannot access `http://192.168.x.x:8080` directly. Only HTTPS via Funnel works.

## Disabling Funnel

If you want to disable Funnel:

```bash
# Stop Funnel
sudo tailscale funnel --https=443 off

# Edit service to remove Funnel line
sudo nano /etc/systemd/system/pihole-trmnl-api.service

# Comment out or remove this line:
# ExecStartPre=/usr/bin/tailscale funnel --bg --https=443 8080

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service
```

**Note:** TRMNL will no longer be able to poll your Pi-hole stats unless you set up an alternative (VPN, reverse proxy, etc.).

## Funnel Bandwidth Limits

Tailscale Funnel has bandwidth limits:
- **Free Personal:** 10 GB/month
- **Paid Plans:** Higher limits

**Pi-hole TRMNL usage:**
- Each poll: ~2-5 KB
- Polling every 10 minutes: ~720 KB/day
- Monthly usage: ~21 MB/month

**Conclusion:** Well within free tier limits!

## Further Reading

- [Tailscale Funnel Documentation](https://tailscale.com/kb/1223/funnel)
- [Tailscale MagicDNS](https://tailscale.com/kb/1081/magicdns)
- [Tailscale Pricing](https://tailscale.com/pricing)

## Getting Help

**Check status:**
```bash
# Service status
sudo systemctl status pihole-trmnl-api.service

# Funnel status
sudo tailscale funnel status

# Recent logs
sudo journalctl -u pihole-trmnl-api.service -n 50
```

**Still having issues?**
1. Check this troubleshooting guide
2. Review service logs
3. Verify Tailscale is connected
4. Test local endpoint first, then HTTPS

---

**Your Pi-hole TRMNL monitor is now accessible securely from anywhere in the world! 🎉**
