#!/bin/bash
# Update script for Pi-hole TRMNL Monitor
# Updates to the latest version from GitHub

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/pihole-trmnl"
SERVICE_NAME="pihole-trmnl-api"
GITHUB_RAW_URL="https://raw.githubusercontent.com/YOUR_USERNAME/pihole-trmnl/main/pihole-plugin/easy-install"

print_header() {
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

main() {
    clear
    print_header "Pi-hole TRMNL Monitor - Update"
    echo

    # Check if running as non-root
    if [[ $EUID -eq 0 ]]; then
        print_error "Don't run this script as root. Run as normal user with sudo."
        exit 1
    fi

    # Check if installed
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "Pi-hole TRMNL Monitor is not installed"
        print_info "Run install.sh first to install"
        exit 1
    fi

    if ! systemctl list-unit-files | grep -q ${SERVICE_NAME}.service; then
        print_error "System service not found"
        print_info "Installation may be incomplete. Consider reinstalling."
        exit 1
    fi

    print_success "Current installation detected"

    # Backup current configuration
    print_header "Backing Up Configuration"

    BACKUP_DIR="/tmp/pihole-trmnl-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Backup service file to extract credentials
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        sudo cp "/etc/systemd/system/${SERVICE_NAME}.service" "$BACKUP_DIR/"
        print_success "Configuration backed up to: $BACKUP_DIR"
    fi

    # Stop service
    print_header "Stopping Service"

    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        sudo systemctl stop ${SERVICE_NAME}.service
        print_success "Service stopped"
    fi

    # Download latest files
    print_header "Downloading Latest Version"

    print_info "Downloading pihole_api_server.py..."
    if curl -fsSL "$GITHUB_RAW_URL/pihole_api_server.py" -o "$INSTALL_DIR/pihole_api_server.py.new" 2>/dev/null; then
        mv "$INSTALL_DIR/pihole_api_server.py.new" "$INSTALL_DIR/pihole_api_server.py"
        chmod +x "$INSTALL_DIR/pihole_api_server.py"
        print_success "Server script updated"
    else
        print_warning "Failed to download server script (keeping existing)"
    fi

    print_info "Downloading pihole-led.liquid template..."
    if curl -fsSL "$GITHUB_RAW_URL/pihole-led.liquid" -o "$INSTALL_DIR/pihole-led.liquid.new" 2>/dev/null; then
        mv "$INSTALL_DIR/pihole-led.liquid.new" "$INSTALL_DIR/pihole-led.liquid"
        print_success "Template updated"
    else
        print_warning "Failed to download template (keeping existing)"
    fi

    # Update Python packages
    print_header "Updating Python Packages"

    print_info "Updating pip..."
    $INSTALL_DIR/venv/bin/pip install -q --upgrade pip
    print_success "pip updated"

    print_info "Updating Flask and dependencies..."
    $INSTALL_DIR/venv/bin/pip install -q --upgrade flask requests urllib3
    print_success "Python packages updated"

    # Restart service
    print_header "Restarting Service"

    sudo systemctl daemon-reload
    sudo systemctl start ${SERVICE_NAME}.service

    # Wait for service to start
    sleep 3

    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "Service restarted successfully"
    else
        print_error "Service failed to start after update"
        print_error "Check logs with: sudo journalctl -u ${SERVICE_NAME}.service -n 50"
        echo
        print_info "Restoring from backup..."
        if [ -f "$BACKUP_DIR/${SERVICE_NAME}.service" ]; then
            sudo cp "$BACKUP_DIR/${SERVICE_NAME}.service" "/etc/systemd/system/"
            sudo systemctl daemon-reload
            sudo systemctl start ${SERVICE_NAME}.service
            print_warning "Backup restored. Update failed."
        fi
        exit 1
    fi

    # Test endpoint
    print_header "Testing Updated Installation"

    # Extract API token from service file
    API_TOKEN=$(sudo grep "API_TOKEN=" /etc/systemd/system/${SERVICE_NAME}.service | cut -d'=' -f2 | tr -d '"')

    sleep 2
    TEST_RESPONSE=$(curl -s "http://localhost:8080/stats?token=$API_TOKEN" 2>/dev/null || echo "")

    if echo "$TEST_RESPONSE" | grep -q "total_queries"; then
        print_success "Endpoint is responding correctly"
    else
        print_warning "Endpoint test inconclusive (may need more time)"
    fi

    # Cleanup backup
    print_header "Update Complete"

    echo
    print_success "Pi-hole TRMNL Monitor updated successfully!"
    echo
    print_info "Backup saved at: $BACKUP_DIR"
    print_info "You can safely delete this backup after confirming everything works"
    echo
    print_info "Check status with: sudo systemctl status ${SERVICE_NAME}.service"
    echo
}

main
