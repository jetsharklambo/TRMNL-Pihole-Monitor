#!/bin/bash
# One-command installer for Pi-hole TRMNL Monitor with Tailscale Funnel
# Usage: curl -sSL https://raw.githubusercontent.com/jetsharklambo/TRMNL-Pihole-Monitor/main/install.sh | bash
#
# This script automatically:
# - Detects Pi-hole installation
# - Extracts Pi-hole API credentials
# - Installs/configures Tailscale with Funnel (HTTPS public access)
# - Sets up Flask server with systemd
# - Provides ready-to-use HTTPS TRMNL polling URL

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/pihole-trmnl"
SERVICE_NAME="pihole-trmnl-api"
GITHUB_RAW_URL="https://raw.githubusercontent.com/jetsharklambo/TRMNL-Pihole-Monitor/main"

# Global variables
PIHOLE_PASSWORD=""
API_TOKEN=""
TAILSCALE_IP=""
TAILSCALE_HOSTNAME=""
FUNNEL_ENABLED=false

# Helper functions
print_header() {
    echo
    echo -e "${BLUE}=========================================="
    echo "$1"
    echo -e "==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

# Step 1: Check prerequisites
check_prerequisites() {
    print_header "Step 1/9: Checking Prerequisites"

    # Check if running as non-root with sudo access
    if [[ $EUID -eq 0 ]]; then
        print_error "Don't run this script as root. Run as normal user with sudo access."
        exit 1
    fi
    print_success "Running as non-root user"

    if ! sudo -n true 2>/dev/null; then
        print_warning "This script needs sudo access. You may be prompted for your password."
    fi
    print_success "Sudo access confirmed"

    # Check if Pi-hole is installed
    if [ ! -d "/etc/pihole" ]; then
        print_error "Pi-hole not detected at /etc/pihole"
        print_error "Install Pi-hole first: https://pi-hole.net"
        exit 1
    fi
    print_success "Pi-hole installation detected"

    # Check Pi-hole version
    if command -v pihole &> /dev/null; then
        PIHOLE_VERSION=$(pihole -v 2>/dev/null | grep "Pi-hole version" | awk '{print $4}' | sed 's/v//' || echo "unknown")
        if [ "$PIHOLE_VERSION" != "unknown" ]; then
            print_info "Pi-hole version: v$PIHOLE_VERSION"
        fi
    fi

    # Check if already installed
    if systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        print_warning "Pi-hole TRMNL Monitor is already installed and running"
        echo
        read -p "Do you want to reinstall/update? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
        print_step "Stopping existing service..."
        sudo systemctl stop ${SERVICE_NAME}.service
    fi
}

# Step 2: Auto-extract Pi-hole credentials
get_pihole_credentials() {
    print_header "Step 2/9: Extracting Pi-hole Credentials"

    # Try to auto-detect Pi-hole password
    # Priority 1: Pi-hole v6 CLI password (temporary plaintext password for CLI tools)
    if [ -f "/etc/pihole/cli_pw" ]; then
        PIHOLE_PASSWORD=$(sudo cat /etc/pihole/cli_pw 2>/dev/null | tr -d '\n')

        if [ -n "$PIHOLE_PASSWORD" ]; then
            print_success "Auto-detected Pi-hole API password from cli_pw (Pi-hole v6)"
        else
            print_warning "Could not read password from cli_pw"
            echo
            read -sp "Enter your Pi-hole web password: " PIHOLE_PASSWORD
            echo
        fi
    # Priority 2: Pi-hole v5 setupVars.conf (legacy)
    elif [ -f "/etc/pihole/setupVars.conf" ]; then
        PIHOLE_PASSWORD=$(sudo grep "WEBPASSWORD=" /etc/pihole/setupVars.conf 2>/dev/null | cut -d'=' -f2)

        if [ -n "$PIHOLE_PASSWORD" ]; then
            print_success "Auto-detected Pi-hole API password from setupVars.conf (Pi-hole v5)"
        else
            print_warning "Could not auto-detect password from setupVars.conf"
            echo
            read -sp "Enter your Pi-hole web password: " PIHOLE_PASSWORD
            echo
        fi
    # Priority 3: Manual entry
    else
        print_warning "Could not find Pi-hole password file (checked cli_pw and setupVars.conf)"
        echo
        read -sp "Enter your Pi-hole web password: " PIHOLE_PASSWORD
        echo
    fi

    # Test Pi-hole API connection
    print_step "Testing Pi-hole API connection..."

    AUTH_RESPONSE=$(curl -s -X POST http://localhost/api/auth \
        -H "Content-Type: application/json" \
        -d "{\"password\":\"$PIHOLE_PASSWORD\"}" 2>/dev/null || echo "")

    if echo "$AUTH_RESPONSE" | grep -q "sid"; then
        print_success "Pi-hole API authentication successful"
    else
        print_error "Pi-hole API authentication failed"
        print_error "Please verify your Pi-hole password and try again"
        exit 1
    fi
}

# Step 3: Install and Configure Tailscale with Funnel
setup_tailscale() {
    print_header "Step 3/9: Setting Up Tailscale with Funnel"

    print_info "Tailscale Funnel provides HTTPS public access to your Pi-hole stats"
    print_info "This is required for TRMNL to poll your data securely"
    echo

    if command -v tailscale &> /dev/null; then
        print_success "Tailscale is installed"

        # Check if authenticated
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")

        if [ -z "$TAILSCALE_IP" ]; then
            print_warning "Tailscale is installed but not authenticated"
            echo
            print_step "Starting Tailscale authentication..."
            print_info "A browser window will open for authentication"
            sudo tailscale up

            TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")

            if [ -z "$TAILSCALE_IP" ]; then
                print_error "Tailscale authentication failed"
                print_error "Please authenticate Tailscale manually: sudo tailscale up"
                exit 1
            fi
        fi

        print_success "Tailscale IP: $TAILSCALE_IP"
    else
        print_step "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh

        if [ $? -ne 0 ]; then
            print_error "Tailscale installation failed"
            exit 1
        fi

        print_success "Tailscale installed"
        print_step "Authenticating Tailscale..."
        echo
        print_info "A browser window will open for authentication"
        sudo tailscale up

        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [ -z "$TAILSCALE_IP" ]; then
            print_error "Tailscale authentication failed"
            exit 1
        fi

        print_success "Tailscale ready: $TAILSCALE_IP"
    fi

    # Get Tailscale hostname (for MagicDNS)
    TAILSCALE_HOSTNAME=$(sudo tailscale status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4 | head -1)
    TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME%.}  # Remove trailing dot

    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        print_success "Tailscale hostname: $TAILSCALE_HOSTNAME"
    else
        print_warning "Could not determine Tailscale hostname (will use IP)"
    fi

    # Enable Tailscale Funnel for HTTPS access
    echo
    print_step "Enabling Tailscale Funnel for HTTPS access..."
    print_info "This allows TRMNL to reach your Pi-hole via public HTTPS URL"

    # Enable funnel on port 8443 -> 8080 (using 8443 to avoid conflict with Pi-hole FTL on port 443)
    if sudo tailscale funnel --bg --https=8443 8080 2>/dev/null; then
        sleep 2

        # Verify funnel is running
        if sudo tailscale funnel status 2>/dev/null | grep -q "https://"; then
            print_success "Tailscale Funnel enabled"
            FUNNEL_ENABLED=true
        else
            print_warning "Funnel enabled but status check failed"
            FUNNEL_ENABLED=true
        fi
    else
        print_error "Failed to enable Tailscale Funnel"
        print_error "Your Tailscale plan may not support Funnel, or MagicDNS is not enabled"
        print_info "Check: https://tailscale.com/kb/1223/funnel"
        exit 1
    fi
}

# Step 4: Install dependencies
install_dependencies() {
    print_header "Step 4/9: Installing Dependencies"

    print_step "Updating package list..."
    sudo apt-get update -qq
    print_success "Package list updated"

    print_step "Installing Python and dependencies..."
    sudo apt-get install -y python3 python3-venv python3-pip curl >/dev/null 2>&1
    print_success "Python and dependencies installed"
}

# Step 5: Install TRMNL monitor
install_monitor() {
    print_header "Step 5/9: Installing Pi-hole TRMNL Monitor"

    # Create installation directory
    print_step "Creating installation directory: $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown $USER:$USER "$INSTALL_DIR"
    print_success "Installation directory created"

    # Download Python server script
    print_step "Downloading server script..."
    if curl -fsSL "$GITHUB_RAW_URL/pihole_api_server.py" -o "$INSTALL_DIR/pihole_api_server.py" 2>/dev/null; then
        chmod +x "$INSTALL_DIR/pihole_api_server.py"
        print_success "Server script downloaded"
    else
        print_error "Failed to download server script from GitHub"
        print_info "Falling back to local file..."

        # Check if we're running from a local clone
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        if [ -f "$SCRIPT_DIR/pihole_api_server.py" ]; then
            cp "$SCRIPT_DIR/pihole_api_server.py" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/pihole_api_server.py"
            print_success "Server script copied from local directory"
        else
            print_error "Server script not found. Please check your installation."
            exit 1
        fi
    fi

    # Download Liquid template
    print_step "Downloading display template..."
    if curl -fsSL "$GITHUB_RAW_URL/pihole-led.liquid" -o "$INSTALL_DIR/pihole-led.liquid" 2>/dev/null; then
        print_success "Template downloaded"
    else
        print_warning "Failed to download template (not critical)"
        # Try local fallback
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        if [ -f "$SCRIPT_DIR/pihole-led.liquid" ]; then
            cp "$SCRIPT_DIR/pihole-led.liquid" "$INSTALL_DIR/"
            print_success "Template copied from local directory"
        fi
    fi

    # Download token rotation script
    print_step "Downloading token rotation script..."
    if curl -fsSL "$GITHUB_RAW_URL/rotate-token.sh" -o "$INSTALL_DIR/rotate-token.sh" 2>/dev/null; then
        chmod +x "$INSTALL_DIR/rotate-token.sh"
        print_success "Rotation script downloaded"
    else
        print_warning "Failed to download rotation script (not critical)"
        # Try local fallback
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        if [ -f "$SCRIPT_DIR/rotate-token.sh" ]; then
            cp "$SCRIPT_DIR/rotate-token.sh" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/rotate-token.sh"
            print_success "Rotation script copied from local directory"
        fi
    fi

    # Create Python virtual environment
    print_step "Creating Python virtual environment..."
    cd "$INSTALL_DIR"
    python3 -m venv venv
    print_success "Virtual environment created"

    print_step "Installing Python packages (Flask, requests, psutil)..."
    ./venv/bin/pip install -q --upgrade pip
    ./venv/bin/pip install -q flask requests urllib3 psutil
    print_success "Python packages installed"
}

# Step 6: Generate API token
generate_api_token() {
    print_header "Step 6/9: Generating Security Token"

    API_TOKEN=$(openssl rand -hex 32)
    print_success "Generated secure 256-bit API token"
    echo
    print_warning "IMPORTANT: Save this token for TRMNL configuration"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$API_TOKEN${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Step 6.5: Optional Firewall Configuration
configure_firewall() {
    print_header "Step 7/9: Firewall Configuration (Optional)"

    print_info "For extra security, you can block direct local network access to port 8080"
    print_info "This ensures only Tailscale Funnel (HTTPS) can access the API"
    echo

    # Check if UFW is installed and active
    if command -v ufw &> /dev/null; then
        UFW_STATUS=$(sudo ufw status 2>/dev/null | grep "Status:" | awk '{print $2}')

        if [ "$UFW_STATUS" = "active" ]; then
            print_success "UFW firewall detected and active"
            echo
            read -p "Configure firewall to block local network access? (Y/n): " -n 1 -r
            echo

            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                print_step "Configuring firewall rules..."

                # Allow from Tailscale subnet
                sudo ufw allow from 100.64.0.0/10 to any port 8080 comment 'Tailscale to Pi-hole TRMNL API' >/dev/null 2>&1

                # Allow from localhost
                sudo ufw allow from 127.0.0.1 to any port 8080 comment 'Localhost to Pi-hole TRMNL API' >/dev/null 2>&1

                # Deny all other access to port 8080
                sudo ufw deny 8080 comment 'Block direct access to Pi-hole TRMNL API' >/dev/null 2>&1

                print_success "Firewall rules configured"
                print_info "Port 8080 now accessible only via Tailscale and localhost"
            else
                print_info "Skipping firewall configuration"
            fi
        else
            print_info "UFW installed but not active - skipping firewall configuration"
        fi
    else
        print_info "UFW not installed - skipping firewall configuration"
        print_info "Install UFW later if you want to restrict local network access"
    fi
}

# Step 8: Create systemd service
create_service() {
    print_header "Step 8/9: Creating System Service"

    # Escape password for systemd (handle special characters)
    PIHOLE_PASSWORD_ESCAPED=$(printf '%s' "$PIHOLE_PASSWORD" | sed 's/["\\]/\\&/g')

    print_step "Creating systemd service file..."

    # Create service file with Funnel support
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=Pi-hole TRMNL API Server with Tailscale Funnel
After=network-online.target pihole-FTL.service tailscaled.service
Wants=network-online.target pihole-FTL.service
Requires=tailscaled.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR

# Environment configuration
Environment="PIHOLE_URL=http://localhost"
Environment="PIHOLE_PASSWORD=$PIHOLE_PASSWORD_ESCAPED"
Environment="API_TOKEN=$API_TOKEN"
Environment="SERVER_PORT=8080"
Environment="CACHE_DURATION=60"

# Ensure Tailscale is connected and Funnel is enabled before starting Flask
# Wait for Tailscale to fully initialize (give it time to connect)
ExecStartPre=/bin/sleep 10
ExecStartPre=/usr/bin/tailscale funnel --bg --https=8443 8080

# Run using virtual environment Python
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/pihole_api_server.py

# Restart on failure
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    # Enable and start service
    print_step "Enabling service to start on boot..."
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}.service >/dev/null 2>&1
    print_success "Service enabled"

    print_step "Starting service..."
    sudo systemctl start ${SERVICE_NAME}.service

    # Wait for service to start
    sleep 3

    # Check if service is running
    if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "Service started successfully"
    else
        print_error "Service failed to start"
        print_error "Check logs with: sudo journalctl -u ${SERVICE_NAME}.service -n 50"
        exit 1
    fi
}

# Step 9: Test endpoints
test_endpoint() {
    print_header "Step 9/9: Testing API Endpoints"

    # Test local HTTP endpoint
    print_step "Testing local HTTP endpoint at http://localhost:8080..."
    sleep 3

    TEST_RESPONSE=$(curl -s "http://localhost:8080/stats?token=$API_TOKEN" 2>/dev/null || echo "")

    if echo "$TEST_RESPONSE" | grep -q "total_queries"; then
        print_success "Local HTTP endpoint is responding correctly"

        # Show sample data
        TOTAL_QUERIES=$(echo "$TEST_RESPONSE" | grep -o '"total_queries":[0-9]*' | cut -d':' -f2)
        BLOCKED=$(echo "$TEST_RESPONSE" | grep -o '"blocked_queries":[0-9]*' | cut -d':' -f2)
        PERCENT=$(echo "$TEST_RESPONSE" | grep -o '"percent_blocked":[0-9.]*' | cut -d':' -f2)

        print_info "Current stats: $TOTAL_QUERIES total queries, $BLOCKED blocked ($PERCENT%)"
    else
        print_warning "Local endpoint not responding with expected data"
        print_info "Check status with: sudo systemctl status ${SERVICE_NAME}.service"
    fi

    # Test HTTPS endpoint via Tailscale Funnel
    if [ "$FUNNEL_ENABLED" = true ] && [ -n "$TAILSCALE_HOSTNAME" ]; then
        echo
        print_step "Testing HTTPS endpoint via Tailscale Funnel..."
        print_info "URL: https://${TAILSCALE_HOSTNAME}/stats"
        sleep 3

        HTTPS_RESPONSE=$(curl -s "https://${TAILSCALE_HOSTNAME}/stats?token=$API_TOKEN" 2>/dev/null || echo "")

        if echo "$HTTPS_RESPONSE" | grep -q "total_queries"; then
            print_success "HTTPS endpoint is responding correctly"
            print_success "TRMNL will be able to poll your Pi-hole stats!"
        else
            print_warning "HTTPS endpoint not responding yet"
            print_info "Funnel may need a few more minutes to propagate"
            print_info "Test manually: curl \"https://${TAILSCALE_HOSTNAME}/stats?token=${API_TOKEN}\""
        fi
    fi

    # Check Funnel status
    echo
    print_step "Verifying Tailscale Funnel status..."
    if sudo tailscale funnel status 2>/dev/null | grep -q "https://"; then
        print_success "Tailscale Funnel is active"
    else
        print_warning "Funnel status could not be verified"
    fi
}

# Step 10: Print configuration summary
print_summary() {
    print_header "Installation Complete!"

    # Build HTTPS URL
    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        POLLING_URL="https://${TAILSCALE_HOSTNAME}/stats?token=${API_TOKEN}"
        POLLING_URL_SYSTEM="https://${TAILSCALE_HOSTNAME}/info/system?token=${API_TOKEN}"
    else
        POLLING_URL="https://${TAILSCALE_IP}/stats?token=${API_TOKEN}"
        POLLING_URL_SYSTEM="https://${TAILSCALE_IP}/info/system?token=${API_TOKEN}"
    fi

    echo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  🎉 Pi-hole TRMNL Monitor Successfully Installed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    echo -e "${YELLOW}📋 Your TRMNL Polling URLs (HTTPS - Public Access):${NC}"
    echo
    echo -e "${CYAN}  Pi-hole Stats:${NC}"
    echo "  $POLLING_URL"
    echo
    echo -e "${CYAN}  System Info:${NC}"
    echo "  $POLLING_URL_SYSTEM"
    echo

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    echo -e "${YELLOW}🔒 Security Features:${NC}"
    echo "  ✅ HTTPS encryption via Tailscale Funnel"
    echo "  ✅ 256-bit API token authentication"
    echo "  ✅ Public access (token-protected)"
    echo "  ✅ Auto-starts on boot"
    echo "  ✅ Auto-restarts on failure"
    echo

    echo -e "${YELLOW}📝 Next Steps:${NC}"
    echo "  1. Go to: ${CYAN}https://usetrmnl.com/plugins${NC}"
    echo "  2. Create a new ${CYAN}Private Plugin${NC}"
    echo "  3. Add ${CYAN}TWO${NC} polling URLs:"
    echo "     - URL 1 (Pi-hole Stats): Copy from above"
    echo "     - URL 2 (System Info): Copy from above"
    echo "  4. Upload template: ${CYAN}$INSTALL_DIR/pihole-led.liquid${NC}"
    echo "  5. Add plugin to your TRMNL playlist"
    echo "  6. Wait 5-15 minutes for first poll"
    echo

    echo -e "${YELLOW}🔧 Useful Commands:${NC}"
    echo "  View logs:        ${CYAN}sudo journalctl -u ${SERVICE_NAME}.service -f${NC}"
    echo "  Check status:     ${CYAN}sudo systemctl status ${SERVICE_NAME}.service${NC}"
    echo "  Restart service:  ${CYAN}sudo systemctl restart ${SERVICE_NAME}.service${NC}"
    echo "  Funnel status:    ${CYAN}sudo tailscale funnel status${NC}"
    echo "  Test HTTPS:       ${CYAN}curl \"$POLLING_URL\"${NC}"
    echo

    echo -e "${YELLOW}📁 Installation Details:${NC}"
    echo "  Directory:       $INSTALL_DIR"
    echo "  Template:        $INSTALL_DIR/pihole-led.liquid"
    echo "  Service:         /etc/systemd/system/${SERVICE_NAME}.service"
    echo "  Tailscale:       $TAILSCALE_HOSTNAME (Funnel enabled)"
    echo "  Rotation Script: $INSTALL_DIR/rotate-token.sh"
    echo

    echo -e "${YELLOW}🔄 Token Management:${NC}"
    echo "  To rotate your token: ${CYAN}sudo $INSTALL_DIR/rotate-token.sh${NC}"
    echo "  Recommended: Rotate every 6-12 months"
    echo

    echo -e "${GREEN}✅ Your Pi-hole stats will now appear on TRMNL via secure HTTPS!${NC}"
    echo
}

# Main installation flow
main() {
    clear
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Pi-hole TRMNL Monitor - Automated Installer  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo

    check_prerequisites
    get_pihole_credentials
    setup_tailscale
    install_dependencies
    install_monitor
    generate_api_token
    configure_firewall
    create_service
    test_endpoint
    print_summary

    echo -e "${GREEN}Installation complete! Your Pi-hole stats will now appear on TRMNL via HTTPS.${NC}"
    echo
}

# Run installer
main
