#!/bin/bash
# Token Rotation Script for Pi-hole TRMNL Monitor
# Safely rotates the API token with automatic rollback on failure
#
# Usage: sudo /opt/pihole-trmnl/rotate-token.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SERVICE_FILE="/etc/systemd/system/pihole-trmnl-api.service"
SERVICE_NAME="pihole-trmnl-api"
BACKUP_FILE="/tmp/pihole-trmnl-token-backup-$(date +%Y%m%d-%H%M%S).txt"

# Global variables
OLD_TOKEN=""
NEW_TOKEN=""
TAILSCALE_HOSTNAME=""

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

# Step 1: Prerequisites check
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if running with sudo
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run with sudo"
        print_info "Usage: sudo $0"
        exit 1
    fi
    print_success "Running with sudo"

    # Check if service file exists
    if [ ! -f "$SERVICE_FILE" ]; then
        print_error "Service file not found: $SERVICE_FILE"
        print_error "Pi-hole TRMNL Monitor may not be installed"
        exit 1
    fi
    print_success "Service file found"

    # Check if service is running
    if ! systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        print_warning "Service is not currently running"
        print_info "The token will still be rotated, but service needs to be started manually"
    else
        print_success "Service is running"
    fi

    # Check if Tailscale is available
    if ! command -v tailscale &> /dev/null; then
        print_warning "Tailscale not found"
        print_info "You'll need to use local IP for testing"
    else
        # Check if Tailscale is connected
        if ! tailscale status &> /dev/null; then
            print_warning "Tailscale is not connected"
        else
            print_success "Tailscale is connected"
        fi
    fi

    echo
}

# Step 2: Backup current token
backup_current_token() {
    print_header "Backing Up Current Token"

    # Extract current token from service file
    OLD_TOKEN=$(grep "API_TOKEN=" $SERVICE_FILE | cut -d'=' -f2 | tr -d '"')

    if [ -z "$OLD_TOKEN" ]; then
        print_error "Could not extract current token from service file"
        exit 1
    fi

    # Save to backup file
    echo "$OLD_TOKEN" > "$BACKUP_FILE"
    chmod 600 "$BACKUP_FILE"

    print_success "Current token backed up to: $BACKUP_FILE"
    print_info "Token: ${OLD_TOKEN:0:16}...${OLD_TOKEN: -16}"
    echo
}

# Step 3: Generate new token
generate_new_token() {
    print_header "Generating New Token"

    NEW_TOKEN=$(openssl rand -hex 32)

    if [ -z "$NEW_TOKEN" ] || [ ${#NEW_TOKEN} -ne 64 ]; then
        print_error "Failed to generate valid token"
        exit 1
    fi

    print_success "Generated new 256-bit token"
    print_info "New token: ${NEW_TOKEN:0:16}...${NEW_TOKEN: -16}"
    echo
}

# Step 4: Update service file
update_service_file() {
    print_header "Updating Service Configuration"

    # Create backup of service file
    cp "$SERVICE_FILE" "${SERVICE_FILE}.backup"
    print_info "Created service file backup"

    # Replace token using sed
    sed -i "s/API_TOKEN=.*/API_TOKEN=$NEW_TOKEN/" "$SERVICE_FILE"

    # Verify the replacement worked
    UPDATED_TOKEN=$(grep "API_TOKEN=" $SERVICE_FILE | cut -d'=' -f2 | tr -d '"')

    if [ "$UPDATED_TOKEN" != "$NEW_TOKEN" ]; then
        print_error "Token replacement failed"
        print_info "Restoring from backup..."
        mv "${SERVICE_FILE}.backup" "$SERVICE_FILE"
        exit 1
    fi

    print_success "Service file updated with new token"
    echo
}

# Step 5: Restart service
restart_service() {
    print_header "Restarting Service"

    print_info "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Daemon reloaded"

    print_info "Restarting ${SERVICE_NAME} service..."
    systemctl restart ${SERVICE_NAME}.service

    # Wait for service to initialize
    print_info "Waiting for service to start..."
    sleep 5

    # Check if service is running
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "Service restarted successfully"
    else
        print_error "Service failed to start with new token"
        return 1
    fi

    echo
}

# Step 6: Test new token
test_new_token() {
    print_header "Testing New Token"

    print_info "Testing health endpoint..."

    # Test health endpoint (no token required)
    if curl -s --max-time 5 "http://localhost:8080/health" | grep -q "healthy"; then
        print_success "Health endpoint responding"
    else
        print_warning "Health endpoint not responding (service may still be starting)"
    fi

    # Test stats endpoint with new token
    print_info "Testing stats endpoint with new token..."
    STATS_RESPONSE=$(curl -s --max-time 5 "http://localhost:8080/stats?token=$NEW_TOKEN" 2>/dev/null || echo "")

    if echo "$STATS_RESPONSE" | grep -q "total_queries"; then
        print_success "New token is working correctly"
        return 0
    else
        print_error "New token failed authentication"
        return 1
    fi
}

# Step 7: Rollback on failure
rollback() {
    print_header "Rolling Back Changes"

    print_warning "Restoring old token due to failure..."

    # Restore service file from backup
    if [ -f "${SERVICE_FILE}.backup" ]; then
        mv "${SERVICE_FILE}.backup" "$SERVICE_FILE"
        print_success "Service file restored"
    fi

    # Restart service with old token
    systemctl daemon-reload
    systemctl restart ${SERVICE_NAME}.service

    sleep 3

    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "Service restored with old token"
    else
        print_error "Service failed to start even with old token"
        print_error "Manual intervention required"
    fi

    print_info "Old token: $OLD_TOKEN"
    exit 1
}

# Step 8: Display new URLs
display_new_urls() {
    print_header "Token Rotation Successful!"

    # Get Tailscale hostname
    if command -v tailscale &> /dev/null; then
        TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4 | head -1)
        TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME%.}
    fi

    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        STATS_URL="https://${TAILSCALE_HOSTNAME}/stats?token=${NEW_TOKEN}"
        SYSTEM_URL="https://${TAILSCALE_HOSTNAME}/info/system?token=${NEW_TOKEN}"
    else
        # Fallback to local IP
        LOCAL_IP=$(hostname -I | awk '{print $1}')
        STATS_URL="http://${LOCAL_IP}:8080/stats?token=${NEW_TOKEN}"
        SYSTEM_URL="http://${LOCAL_IP}:8080/info/system?token=${NEW_TOKEN}"
    fi

    echo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  New TRMNL Polling URLs${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${CYAN}  Pi-hole Stats:${NC}"
    echo "  $STATS_URL"
    echo
    echo -e "${CYAN}  System Info:${NC}"
    echo "  $SYSTEM_URL"
    echo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    echo -e "${YELLOW}⚠️  IMPORTANT: Update Your TRMNL Plugin Configuration${NC}"
    echo
    echo "  1. Go to: ${CYAN}https://usetrmnl.com/plugins${NC}"
    echo "  2. Edit your Pi-hole private plugin"
    echo "  3. Update ${CYAN}BOTH${NC} polling URLs with the new URLs above"
    echo "  4. Save changes"
    echo
    echo -e "${YELLOW}Old token has been invalidated and will no longer work.${NC}"
    echo

    print_info "Token Details:"
    echo "  Old token: ${OLD_TOKEN:0:16}...${OLD_TOKEN: -16}"
    echo "  New token: ${NEW_TOKEN:0:16}...${NEW_TOKEN: -16}"
    echo "  Backup:    $BACKUP_FILE"
    echo

    print_success "Token rotation complete!"
    echo
}

# Main execution
main() {
    clear
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Pi-hole TRMNL Monitor - Token Rotation    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo

    # Confirmation prompt
    print_warning "This will rotate your API token and invalidate the old token"
    echo
    read -p "Continue with token rotation? (y/N): " -n 1 -r
    echo
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Token rotation cancelled"
        exit 0
    fi

    # Execute rotation steps
    check_prerequisites
    backup_current_token
    generate_new_token
    update_service_file

    # Restart and test (with rollback on failure)
    if ! restart_service; then
        rollback
    fi

    if ! test_new_token; then
        rollback
    fi

    # Clean up backup service file on success
    rm -f "${SERVICE_FILE}.backup"

    display_new_urls

    print_info "Backup token file will remain at: $BACKUP_FILE"
    print_info "You can safely delete it after confirming the new token works"
    echo
}

# Run main function
main
