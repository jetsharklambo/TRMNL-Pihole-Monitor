#!/bin/bash
# Uninstall script for Pi-hole TRMNL Monitor
# Removes all components installed by install.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/pihole-trmnl"
SERVICE_NAME="pihole-trmnl-api"

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
    echo -e "${BLUE}ℹ${NC}  $1"
}

main() {
    clear
    print_header "Pi-hole TRMNL Monitor - Uninstaller"
    echo

    # Check if running as non-root
    if [[ $EUID -eq 0 ]]; then
        print_error "Don't run this script as root. Run as normal user with sudo."
        exit 1
    fi

    # Confirm uninstallation
    print_warning "This will remove Pi-hole TRMNL Monitor from your system"
    echo
    read -p "Are you sure you want to uninstall? (y/N): " -n 1 -r
    echo
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi

    # Stop and disable service
    print_header "Removing System Service"

    if systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        print_info "Stopping service..."
        sudo systemctl stop ${SERVICE_NAME}.service
        print_success "Service stopped"
    else
        print_info "Service is not running"
    fi

    if systemctl is-enabled --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        print_info "Disabling service..."
        sudo systemctl disable ${SERVICE_NAME}.service >/dev/null 2>&1
        print_success "Service disabled"
    fi

    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        print_info "Removing service file..."
        sudo rm /etc/systemd/system/${SERVICE_NAME}.service
        sudo systemctl daemon-reload
        print_success "Service file removed"
    fi

    # Disable Tailscale Funnel
    print_header "Disabling Tailscale Funnel"

    if command -v tailscale &> /dev/null; then
        # Check if Funnel is running
        if sudo tailscale funnel status 2>/dev/null | grep -q "https://"; then
            FUNNEL_URL=$(sudo tailscale funnel status 2>/dev/null | grep "https://" | awk '{print $NF}' | head -1)
            print_info "Disabling Tailscale Funnel: $FUNNEL_URL"
            sudo tailscale funnel --https=443 off 2>/dev/null || true
            print_success "Tailscale Funnel disabled"
        else
            print_info "Tailscale Funnel not active (already disabled or not configured)"
        fi
    else
        print_info "Tailscale not installed (skipping Funnel cleanup)"
    fi
    echo

    # Remove installation directory
    print_header "Removing Installation Files"

    if [ -d "$INSTALL_DIR" ]; then
        print_info "Removing installation directory: $INSTALL_DIR"
        sudo rm -rf "$INSTALL_DIR"
        print_success "Installation directory removed"
    else
        print_info "Installation directory not found (already removed)"
    fi

    # Ask about firewall rules cleanup
    print_header "Firewall Cleanup (Optional)"

    if command -v ufw &> /dev/null; then
        if sudo ufw status 2>/dev/null | grep -q "8080"; then
            echo
            print_info "UFW firewall rules for port 8080 detected"
            print_info "These rules were created to restrict access to the Pi-hole TRMNL API"
            echo
            read -p "Remove firewall rules for port 8080? (y/N): " -n 1 -r
            echo
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_info "Removing firewall rules..."
                # Remove Tailscale allow rule
                sudo ufw delete allow from 100.64.0.0/10 to any port 8080 2>/dev/null || true
                # Remove localhost allow rule
                sudo ufw delete allow from 127.0.0.1 to any port 8080 2>/dev/null || true
                # Remove deny rule
                sudo ufw delete deny 8080 2>/dev/null || true
                print_success "Firewall rules removed"
            else
                print_info "Keeping firewall rules"
            fi
        else
            print_info "No firewall rules found for port 8080"
        fi
    else
        print_info "UFW not installed (skipping firewall cleanup)"
    fi
    echo

    # Ask about Python packages (optional)
    print_header "Cleanup Python Packages (Optional)"
    echo
    print_info "The following Python packages were installed:"
    print_info "  - flask"
    print_info "  - requests"
    print_info "  - urllib3"
    print_info "  - psutil"
    echo
    print_warning "These packages may be used by other applications"
    echo
    read -p "Remove Python packages? (y/N): " -n 1 -r
    echo
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removing Python packages..."
        pip3 uninstall -y flask requests urllib3 psutil 2>/dev/null || true
        print_success "Python packages removed"
    else
        print_info "Keeping Python packages"
    fi

    # Enhanced Tailscale cleanup options
    if command -v tailscale &> /dev/null; then
        echo
        print_header "Tailscale Cleanup (Optional)"
        echo
        print_info "Tailscale is installed on this system"
        print_warning "Tailscale may be used by other services"
        echo
        print_info "Choose an option:"
        echo "  1 - Keep Tailscale (recommended if used elsewhere)"
        echo "  2 - Disconnect from Tailscale network only"
        echo "  3 - Fully remove Tailscale"
        echo
        read -p "Enter choice (1/2/3): " -n 1 -r
        echo
        echo

        case $REPLY in
            1)
                print_info "Keeping Tailscale unchanged"
                ;;
            2)
                print_info "Disconnecting from Tailscale network..."
                sudo tailscale down 2>/dev/null || true
                print_success "Disconnected from Tailscale (software still installed)"
                ;;
            3)
                print_info "Fully removing Tailscale..."
                sudo tailscale down 2>/dev/null || true
                sudo apt-get remove -y tailscale 2>/dev/null || true
                sudo apt-get autoremove -y 2>/dev/null || true
                print_success "Tailscale removed"
                ;;
            *)
                print_info "Invalid choice - keeping Tailscale unchanged"
                ;;
        esac
    fi

    # Final summary
    echo
    print_header "Uninstall Complete"
    echo
    print_success "Pi-hole TRMNL Monitor has been removed"
    echo
    print_info "What was removed:"
    echo "  ✓ System service (${SERVICE_NAME})"
    echo "  ✓ Installation directory ($INSTALL_DIR)"
    echo "  ✓ Service configuration"
    echo "  ✓ Tailscale Funnel configuration"
    echo
    print_info "What was kept:"
    echo "  - Pi-hole installation (unchanged)"
    echo "  - System Python installation"
    if command -v tailscale &> /dev/null; then
        echo "  - Tailscale (if not removed above)"
    fi
    echo

    # Verify Funnel status
    if command -v tailscale &> /dev/null; then
        print_info "Tailscale Funnel Status:"
        if sudo tailscale funnel status 2>/dev/null | grep -q "https://"; then
            echo "  ⚠  Funnel is still active (may be used by other services)"
        else
            echo "  ✓  Funnel disabled"
        fi
        echo
    fi

    print_info "To reinstall, run the install script again"
    echo
}

main
