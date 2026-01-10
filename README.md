# Pi-hole TRMNL Monitor - Easy Installation

**One-command installation for Pi-hole TRMNL monitoring with HTTPS public access via Tailscale Funnel.**

## Quick Start

### One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/jetsharklambo/TRMNL-Pihole-Monitor/main/install.sh | bash
```

That's it! The script will:
- ✅ Auto-detect your Pi-hole installation
- ✅ Extract Pi-hole API credentials automatically
- ✅ Install and configure Tailscale with Funnel (HTTPS public access)
- ✅ Set up Flask server with systemd
- ✅ Optional firewall configuration for extra security
- ✅ Start monitoring service (auto-starts on boot)
- ✅ Provide your ready-to-use HTTPS TRMNL polling URL

**Installation time: ~5-7 minutes** (includes Tailscale Funnel setup)

## What Gets Installed

| Component | Location | Purpose |
|-----------|----------|---------|
| Flask API Server | `/opt/pihole-trmnl/pihole_api_server.py` | Serves Pi-hole & system stats |
| Python Virtual Env | `/opt/pihole-trmnl/venv/` | Isolated Python dependencies |
| Liquid Template | `/opt/pihole-trmnl/pihole-led.liquid` | TRMNL display template |
| Token Rotation Script | `/opt/pihole-trmnl/rotate-token.sh` | Safely rotate API tokens |
| systemd Service | `/etc/systemd/system/pihole-trmnl-api.service` | Auto-start on boot with Funnel |
| Tailscale | System-wide | Secure networking |
| Tailscale Funnel | Enabled on port 443→8080 | HTTPS public access |
| Firewall Rules (optional) | UFW | Block local network access to port 8080 |

## Available Endpoints

The Flask server provides two endpoints:

1. **`/stats`** - Pi-hole statistics
   - Total queries, blocked queries, block percentage
   - Active clients, blocklist size, cache hits
   - Pi-hole enabled/disabled status

2. **`/info/system`** - System monitoring
   - RAM usage (percent, used/total MB)
   - CPU usage (percent, core count)
   - System uptime (seconds, formatted as days/hours/minutes)

## Requirements

- **Pi-hole v6+** with FTL API
- **Debian/Ubuntu/Raspbian** based system
- **Sudo access**
- **Internet connection** (for downloading dependencies)

## Key Features

### 🔒 Security
- **HTTPS Encryption** - Tailscale Funnel provides automatic TLS certificates
- **Token Authentication** - 256-bit cryptographic tokens protect your data
- **Easy Token Rotation** - One-command script for rotating tokens safely
- **Optional Firewall** - Block local network access, force HTTPS-only
- **No Port Forwarding** - Your home IP stays hidden

### 🚀 Ease of Use
- **One-Command Install** - Fully automated setup in 5-7 minutes
- **Auto-Discovery** - Detects Pi-hole configuration automatically
- **Auto-Start** - Service runs on boot with automatic restarts
- **Public Access** - TRMNL can poll from anywhere (no VPN required)
- **Clean Uninstall** - Complete removal with one command

### 📊 Monitoring
- **Pi-hole Stats** - DNS queries, blocks, clients, blocklist size
- **System Stats** - CPU, RAM, disk usage, uptime
- **Dual Endpoints** - Separate URLs for Pi-hole and system data
- **Cached Responses** - Efficient polling with minimal load

## Installation Details

### What the Script Does

**Step 1: Prerequisites Check**
- Verifies Pi-hole is installed
- Checks sudo access
- Detects if already installed (offers to update)

**Step 2: Auto-Extract Credentials**
- Reads Pi-hole password from `/etc/pihole/setupVars.conf`
- Tests Pi-hole API authentication
- Falls back to manual entry if auto-detection fails

**Step 3: Tailscale Setup with Funnel (Required)**
- Detects if Tailscale is installed
- Installs Tailscale if missing
- Authenticates Tailscale account
- Enables Tailscale Funnel for HTTPS public access
- Retrieves Tailscale hostname for MagicDNS

**Step 4: Install Dependencies**
- Installs Python 3, pip, venv
- Creates isolated virtual environment
- Installs Flask, requests, urllib3, psutil

**Step 5: Download Monitor Files**
- Downloads latest Flask server script
- Downloads TRMNL display template
- Sets proper permissions

**Step 6: Generate Security Token**
- Creates 256-bit random API token
- Displays token for TRMNL configuration

**Step 7: Firewall Configuration (Optional)**
- Detects if UFW firewall is active
- Offers to configure firewall rules
- Blocks local network access to port 8080
- Allows Tailscale and localhost only

**Step 8: Create System Service**
- Creates systemd service file with Funnel support
- Configures auto-start on boot
- Ensures Funnel starts before Flask server
- Enables auto-restart on failure
- Starts the service

**Step 9: Test Installation**
- Tests local HTTP endpoint
- Tests HTTPS endpoint via Tailscale Funnel
- Verifies Funnel status
- Displays current Pi-hole stats

**Step 10: Provide Configuration**
- Shows HTTPS TRMNL polling URLs
- Lists security features
- Provides next steps
- Lists useful commands

**After Installation:**
- Token rotation script ready: `sudo /opt/pihole-trmnl/rotate-token.sh`
- HTTPS URLs work immediately (no DNS propagation wait)
- Service auto-restarts if Pi-hole or network restarts
- Funnel persists across reboots (configured in systemd)

## After Installation

### Your Polling URLs

After installation completes, you'll see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🎉 Pi-hole TRMNL Monitor Successfully Installed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Your TRMNL Polling URLs (HTTPS - Public Access):

  Pi-hole Stats:
  https://your-hostname.ts.net/stats?token=YOUR_GENERATED_TOKEN

  System Info:
  https://your-hostname.ts.net/info/system?token=YOUR_GENERATED_TOKEN

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Configure TRMNL

The plugin includes **system monitoring** (RAM, CPU, uptime) along with Pi-hole stats. You'll need to configure **two polling URLs** in TRMNL:

1. Go to https://usetrmnl.com/plugins
2. Create a new **Private Plugin** (or edit existing)
3. Add **TWO polling URLs** (use HTTPS URLs from installation output):
   - **URL 1 (Pi-hole Stats)**: `https://your-hostname.ts.net/stats?token=YOUR_TOKEN`
   - **URL 2 (System Stats)**: `https://your-hostname.ts.net/info/system?token=YOUR_TOKEN`
4. Upload the Liquid template: `/opt/pihole-trmnl/pihole-led.liquid`
5. Add plugin to your TRMNL playlist
6. Wait for TRMNL to poll (5-15 minutes)

**Note:** TRMNL automatically assigns indices to polling URLs (IDX_0, IDX_1, etc.). The template expects Pi-hole stats in IDX_0 and system stats in IDX_1.

**Important:** Use the **HTTPS URLs** provided at the end of installation, not HTTP URLs.

## Useful Commands

### Service Management

```bash
# View real-time logs
sudo journalctl -u pihole-trmnl-api.service -f

# Check service status
sudo systemctl status pihole-trmnl-api.service

# Restart service
sudo systemctl restart pihole-trmnl-api.service

# Stop service
sudo systemctl stop pihole-trmnl-api.service

# Start service
sudo systemctl start pihole-trmnl-api.service
```

### Test Endpoints

```bash
# Test local endpoint (HTTP)
curl "http://localhost:8080/stats?token=YOUR_TOKEN" | jq

# Test HTTPS endpoint via Tailscale Funnel (what TRMNL uses)
curl "https://your-hostname.ts.net/stats?token=YOUR_TOKEN" | jq
curl "https://your-hostname.ts.net/info/system?token=YOUR_TOKEN" | jq

# Check Tailscale Funnel status
sudo tailscale funnel status
```

### Get Your Token

```bash
# Extract API token from service file
sudo grep "API_TOKEN=" /etc/systemd/system/pihole-trmnl-api.service | cut -d'=' -f2 | tr -d '"'
```

### Check Tailscale Info

```bash
# Get your Tailscale IP address
tailscale ip -4

# Get your Tailscale hostname
tailscale status | grep "$(hostname)"

# Check Funnel status
sudo tailscale funnel status
```

### Token Management

```bash
# Rotate API token (recommended every 6-12 months)
sudo /opt/pihole-trmnl/rotate-token.sh

# View current token
sudo grep "API_TOKEN=" /etc/systemd/system/pihole-trmnl-api.service | cut -d'=' -f2 | tr -d '"'
```

## Updating

To update to the latest version:

```bash
curl -sSL https://raw.githubusercontent.com/jetsharklambo/TRMNL-Pihole-Monitor/main/update.sh | bash
```

The update script:
- ✅ Backs up current configuration
- ✅ Downloads latest version
- ✅ Updates Python packages
- ✅ Restarts service
- ✅ Tests installation
- ✅ Rolls back if update fails

## Token Management

### Rotating Your API Token

For security, it's recommended to rotate your API token every 6-12 months. The installation includes a dedicated script to make this easy and safe.

#### Using the Rotation Script (Recommended)

```bash
# Run the token rotation script
sudo /opt/pihole-trmnl/rotate-token.sh
```

The script will:
- ✅ Generate a new secure 256-bit token
- ✅ Update the service configuration automatically
- ✅ Test the new token
- ✅ Rollback if any errors occur
- ✅ Display new TRMNL polling URLs

**Important:** After rotation completes, you must update both polling URLs in your TRMNL plugin configuration!

#### Manual Token Rotation

If you prefer to rotate the token manually:

```bash
# 1. Generate new token
NEW_TOKEN=$(openssl rand -hex 32)

# 2. Update service file
sudo sed -i "s/API_TOKEN=.*/API_TOKEN=$NEW_TOKEN/" /etc/systemd/system/pihole-trmnl-api.service

# 3. Restart service
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service

# 4. Get new URLs
HOSTNAME=$(tailscale status --json | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4 | sed 's/\.$//')
echo "Stats:  https://$HOSTNAME/stats?token=$NEW_TOKEN"
echo "System: https://$HOSTNAME/info/system?token=$NEW_TOKEN"

# 5. Update TRMNL plugin with new URLs
```

### When to Rotate Tokens

**Rotate your token if:**
- ❗ You suspect the token has been compromised
- ❗ You accidentally shared the URL publicly
- ❗ It's been 6+ months since last rotation
- ❗ You found the token in a git repository or public paste

**Don't rotate automatically** unless you have a way to update TRMNL plugin URLs programmatically.

---

## Uninstalling

To completely remove Pi-hole TRMNL Monitor:

```bash
curl -sSL https://raw.githubusercontent.com/jetsharklambo/TRMNL-Pihole-Monitor/main/uninstall.sh | bash
```

The uninstall script will:
- ✅ Stop and remove systemd service
- ✅ Disable Tailscale Funnel
- ✅ Remove installation directory
- ✅ Optionally remove firewall rules (UFW)
- ✅ Optionally remove Python packages
- ✅ Optionally remove or disconnect Tailscale
- ✅ Leave Pi-hole installation untouched

**Note:** The script provides multiple options for Tailscale cleanup:
1. Keep Tailscale (if used by other services)
2. Disconnect from Tailscale network only
3. Fully remove Tailscale

## Troubleshooting

### Installation Failed

**Check logs:**
```bash
# View last 50 log lines
sudo journalctl -u pihole-trmnl-api.service -n 50

# View all logs since last boot
sudo journalctl -u pihole-trmnl-api.service -b
```

**Common issues:**

| Error | Solution |
|-------|----------|
| "Pi-hole not detected" | Install Pi-hole first: https://pi-hole.net |
| "Authentication failed" | Verify Pi-hole password, check `/etc/pihole/setupVars.conf` |
| "Service failed to start" | Check logs, verify Python dependencies installed |
| "Port 8080 already in use" | Another service using port 8080, change port in service file |
| "Funnel failed to enable" | MagicDNS may not be enabled, check Tailscale admin console |
| "Tailscale plan doesn't support Funnel" | Upgrade to a plan that includes Funnel (free for personal use) |

### Service Won't Start

```bash
# Check service status
sudo systemctl status pihole-trmnl-api.service

# View detailed error messages
sudo journalctl -u pihole-trmnl-api.service -n 100 --no-pager

# Verify Python virtual environment
ls -la /opt/pihole-trmnl/venv/

# Test Python server manually
cd /opt/pihole-trmnl
./venv/bin/python3 pihole_api_server.py
```

### TRMNL Can't Reach Server

**Check Tailscale Funnel:**
```bash
# Verify Funnel is running
sudo tailscale funnel status

# Should show: https://your-hostname.ts.net
# If not, restart service:
sudo systemctl restart pihole-trmnl-api.service
```

**Test HTTPS endpoint:**
```bash
# Test from Pi-hole itself
curl "https://YOUR_HOSTNAME.ts.net/stats?token=YOUR_TOKEN"

# If this works but TRMNL fails, check TRMNL plugin configuration
```

**Check service is running:**
```bash
# Service status
sudo systemctl status pihole-trmnl-api.service

# Recent logs
sudo journalctl -u pihole-trmnl-api.service -n 20
```

**Verify Tailscale is connected:**
```bash
# Should show "Connected" or similar
tailscale status

# If not connected:
sudo tailscale up
```

### Authentication Errors

```bash
# Test Pi-hole API directly
curl -X POST http://localhost/api/auth \
  -H "Content-Type: application/json" \
  -d '{"password":"YOUR_PIHOLE_PASSWORD"}'

# Should return session ID and CSRF token
```

### Endpoint Returns Error

```bash
# Check if Pi-hole FTL is running
sudo systemctl status pihole-FTL.service

# Verify Pi-hole web interface works
curl http://localhost/admin/

# Check server logs for errors
sudo journalctl -u pihole-trmnl-api.service -f
```

## Advanced Configuration

### Change Server Port

Edit the service file:
```bash
sudo nano /etc/systemd/system/pihole-trmnl-api.service
```

Change `SERVER_PORT=8080` to your desired port, then:
```bash
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service
```

### Change Cache Duration

Edit the service file and modify `CACHE_DURATION=60` (seconds):
```bash
sudo nano /etc/systemd/system/pihole-trmnl-api.service
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service
```

### Use Custom Pi-hole URL

If Pi-hole is on a different host:
```bash
sudo nano /etc/systemd/system/pihole-trmnl-api.service
# Change PIHOLE_URL=http://localhost to your Pi-hole IP
sudo systemctl daemon-reload
sudo systemctl restart pihole-trmnl-api.service
```

## Security Notes

### API Token

- **256-bit random token** generated during installation
- Required for all API requests
- Transmitted over HTTPS (encrypted via Tailscale Funnel)
- Never commit to version control
- Regenerate if compromised

### Tailscale Funnel Security

**What Funnel Provides:**
- ✅ **HTTPS encryption** - Token is encrypted in transit
- ✅ **Public access** - TRMNL can reach your Pi-hole from anywhere
- ✅ **No port forwarding** - Your home IP stays hidden
- ✅ **Automatic certificates** - Tailscale handles TLS
- ✅ **No home IP exposure** - Traffic routes through Tailscale infrastructure

**Important Notes:**
- Anyone with the URL + token can access your stats
- Stats are **read-only** (total queries, blocked count, etc.)
- No personal data exposed (no specific domains or client IPs)
- Token provides 256-bit security (practically unguessable)

### Network Access

The Flask server listens on `0.0.0.0:8080`:
- ✅ Accessible from localhost (127.0.0.1)
- ✅ Accessible from local network (unless firewall blocks)
- ✅ Accessible via Tailscale network (100.x.x.x)
- ✅ **Publicly accessible via Tailscale Funnel** (HTTPS only, token-protected)

### Firewall Protection (Optional)

During installation, you can configure UFW to block local network access:

```bash
# Allow from Tailscale subnet
sudo ufw allow from 100.64.0.0/10 to any port 8080

# Allow from localhost
sudo ufw allow from 127.0.0.1 to any port 8080

# Deny all other access
sudo ufw deny 8080
```

**Effect:** Forces all access through Tailscale Funnel (HTTPS), blocking direct HTTP access from local network.

### Data Exposure

The API exposes **aggregated, read-only statistics only**:
- ✅ Total query count
- ✅ Blocked query count
- ✅ Active client count
- ✅ System resources (CPU, RAM, uptime)
- ❌ **NOT exposed:** Specific domains queried, client IP addresses, browsing history

**Privacy Note:** Query counts could reveal usage patterns (e.g., when you're home), but no detailed browsing data is accessible.

## File Structure

```
/opt/pihole-trmnl/
├── pihole_api_server.py      # Flask server
├── pihole-led.liquid          # TRMNL display template
└── venv/                      # Python virtual environment
    ├── bin/
    │   ├── python3
    │   ├── flask
    │   └── pip
    └── lib/
        └── python3.x/
            └── site-packages/
                ├── flask/
                ├── requests/
                └── urllib3/

/etc/systemd/system/
└── pihole-trmnl-api.service   # systemd service file
```

## Quick Reference

### Common Tasks

| Task | Command |
|------|---------|
| View logs | `sudo journalctl -u pihole-trmnl-api.service -f` |
| Restart service | `sudo systemctl restart pihole-trmnl-api.service` |
| Check service status | `sudo systemctl status pihole-trmnl-api.service` |
| Rotate token | `sudo /opt/pihole-trmnl/rotate-token.sh` |
| Check Funnel status | `sudo tailscale funnel status` |
| Get Tailscale hostname | `tailscale status \| grep "$(hostname)"` |
| Test HTTPS endpoint | `curl "https://YOUR-HOSTNAME.ts.net/stats?token=YOUR_TOKEN"` |
| Update to latest | `curl -sSL https://raw.githubusercontent.com/.../update.sh \| bash` |
| Uninstall | `curl -sSL https://raw.githubusercontent.com/.../uninstall.sh \| bash` |

## Performance & Security

**Resource Usage (Pi Zero 2 W):**
- Memory: ~30-50 MB
- CPU: <1% idle, ~5% during requests
- Disk: ~100 MB (including Python venv)

**Network:**
- TRMNL polls every 5-15 minutes
- Each poll: ~2-5 KB data transfer
- Encrypted via HTTPS (Tailscale Funnel)
- Negligible bandwidth impact

**Security:**
- HTTPS encryption protects token in transit
- Token provides 256-bit authentication
- No sensitive data exposed (only aggregate stats)
- Regular token rotation recommended (6-12 months)

## Persistence

Everything is configured to persist across reboots:
- ✅ Service starts automatically on boot
- ✅ Service restarts on failure
- ✅ All configuration saved to disk
- ✅ Python dependencies in virtual environment
- ✅ Tailscale Funnel starts on boot

## Getting Help

1. Check this README troubleshooting section
2. View service logs: `sudo journalctl -u pihole-trmnl-api.service`
3. Test endpoint manually with curl
4. Verify Pi-hole is running: `pihole status`
5. Check TRMNL plugin configuration

## What's Next?

After successful installation:
- [ ] Copy polling URL
- [ ] Configure TRMNL plugin
- [ ] Upload Liquid template
- [ ] Add to TRMNL playlist
- [ ] Wait for first poll (~5-15 minutes)
- [ ] Enjoy Pi-hole stats on your TRMNL display!

## Contributing

Found a bug? Have a suggestion?
- Open an issue on GitHub
- Submit a pull request
- Share your TRMNL display photos!

## License

MIT License - feel free to use and modify.

---

**Made with ❤️ for the TRMNL and Pi-hole communities**
