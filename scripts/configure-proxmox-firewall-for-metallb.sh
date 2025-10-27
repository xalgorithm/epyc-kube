#!/bin/bash

# Configure Proxmox Firewall for MetalLB Subnet
# Focused script to add firewall rules for HTTP/HTTPS access to 10.0.2.8/29

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
METALLB_SUBNET="10.0.2.8/29"
METALLB_FIRST_IP="10.0.2.9"
PROXMOX_HOST="${PROXMOX_HOST:-}"

echo -e "${BLUE}Configure Proxmox Firewall for MetalLB${NC}"
echo -e "${BLUE}=====================================${NC}"

# Function to execute commands (local or remote)
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${YELLOW}$description${NC}"
    
    if [ -n "$PROXMOX_HOST" ]; then
        ssh "$PROXMOX_HOST" "$cmd"
    else
        eval "$cmd"
    fi
}

# Function to check environment
check_environment() {
    if [ -z "$PROXMOX_HOST" ]; then
        if [ -f "/etc/pve/local/pve-ssl.pem" ] || [ -d "/etc/pve" ]; then
            echo -e "${GREEN}✓ Running on Proxmox host${NC}"
        else
            echo -e "${YELLOW}⚠ Not on Proxmox host. Use: PROXMOX_HOST=root@proxmox-ip $0${NC}"
            echo -e "${BLUE}This script needs to run on the Proxmox host to configure iptables${NC}"
            exit 1
        fi
    else
        echo -e "${BLUE}Configuring remote Proxmox host: $PROXMOX_HOST${NC}"
    fi
}

# Function to show current firewall status
show_current_firewall() {
    echo -e "${YELLOW}Current Firewall Configuration:${NC}"
    echo ""
    
    echo -e "${BLUE}Current iptables FORWARD rules:${NC}"
    execute_cmd "iptables -L FORWARD -n --line-numbers | head -20" "Showing FORWARD chain"
    echo ""
    
    echo -e "${BLUE}Current rules for MetalLB subnet:${NC}"
    execute_cmd "(iptables -L FORWARD -n | grep '198\.55\.108') || echo 'No MetalLB rules found'" "Checking MetalLB rules"
    echo ""
    
    echo -e "${BLUE}Testing current connectivity:${NC}"
    execute_cmd "(ping -c 2 -W 2 $METALLB_FIRST_IP && echo 'Ping: OK') || echo 'Ping: FAILED'" "Testing ping"
    execute_cmd "(timeout 5 curl -I http://$METALLB_FIRST_IP 2>/dev/null | head -1) || echo 'HTTP: TIMEOUT/BLOCKED'" "Testing HTTP"
    echo ""
}

# Function to add firewall rules
add_firewall_rules() {
    echo -e "${YELLOW}Adding Firewall Rules for MetalLB Subnet...${NC}"
    
    # Check if rules already exist
    local existing_rules
    existing_rules=$(execute_cmd "(iptables -L FORWARD -n | grep '198\.55\.108' || true) | wc -l" "Checking existing rules")
    
    if [ "$existing_rules" -eq 0 ]; then
        echo -e "${BLUE}Adding new firewall rules...${NC}"
        
        # Add rules for HTTP and HTTPS
        execute_cmd "iptables -I FORWARD 1 -d $METALLB_SUBNET -p tcp --dport 80 -j ACCEPT" "Adding HTTP (port 80) rule"
        execute_cmd "iptables -I FORWARD 1 -d $METALLB_SUBNET -p tcp --dport 443 -j ACCEPT" "Adding HTTPS (port 443) rule"
        
        # Add general rule for MetalLB subnet (for other services)
        execute_cmd "iptables -I FORWARD 1 -d $METALLB_SUBNET -j ACCEPT" "Adding general MetalLB rule"
        
        # Add rule for return traffic
        execute_cmd "iptables -I FORWARD 1 -s $METALLB_SUBNET -j ACCEPT" "Adding return traffic rule"
        
        echo -e "${GREEN}✓ Firewall rules added${NC}"
    else
        echo -e "${GREEN}✓ Firewall rules already exist ($existing_rules rules found)${NC}"
    fi
    echo ""
}

# Function to save firewall rules
save_firewall_rules() {
    echo -e "${YELLOW}Saving Firewall Rules...${NC}"
    
    # Try different methods to save iptables rules
    execute_cmd "mkdir -p /etc/iptables" "Creating iptables directory"
    
    # Try iptables-save first
    echo -e "${YELLOW}Attempting to save with iptables-save...${NC}"
    if execute_cmd "command -v iptables-save >/dev/null 2>&1 && iptables-save > /etc/iptables/rules.v4" "Saving with iptables-save"; then
        echo -e "${GREEN}✓ Rules saved to /etc/iptables/rules.v4${NC}"
    # Try netfilter-persistent as fallback
    elif execute_cmd "command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save" "Saving with netfilter-persistent"; then
        echo -e "${GREEN}✓ Rules saved with netfilter-persistent${NC}"
    else
        echo -e "${YELLOW}⚠ Could not find iptables-save or netfilter-persistent${NC}"
        echo -e "${YELLOW}⚠ Attempting manual save...${NC}"
        execute_cmd "iptables-save > /etc/iptables/rules.v4 || echo 'Manual save failed - please save manually'" "Manual iptables save"
    fi
    echo ""
}

# Function to test firewall configuration
test_firewall_config() {
    echo -e "${YELLOW}Testing Firewall Configuration...${NC}"
    
    echo -e "${BLUE}1. Checking new firewall rules:${NC}"
    execute_cmd "(iptables -L FORWARD -n | grep '198\.55\.108' || echo 'No rules found') | head -5" "Showing MetalLB rules"
    echo ""
    
    echo -e "${BLUE}2. Testing connectivity:${NC}"
    execute_cmd "(ping -c 3 -W 2 $METALLB_FIRST_IP && echo 'Ping: SUCCESS') || echo 'Ping: FAILED'" "Testing ping"
    echo ""
    
    echo -e "${BLUE}3. Testing HTTP access:${NC}"
    execute_cmd "(timeout 10 curl -I http://$METALLB_FIRST_IP 2>&1 | head -3) || echo 'HTTP: Still blocked or no service running'" "Testing HTTP"
    echo ""
    
    echo -e "${BLUE}4. Testing HTTPS access:${NC}"
    execute_cmd "(timeout 10 curl -I -k https://$METALLB_FIRST_IP 2>&1 | head -3) || echo 'HTTPS: Still blocked or no service running'" "Testing HTTPS"
    echo ""
}

# Function to show troubleshooting info
show_troubleshooting() {
    echo -e "${YELLOW}Troubleshooting Information:${NC}"
    echo ""
    
    echo -e "${BLUE}If HTTP/HTTPS still doesn't work, check:${NC}"
    echo -e "${YELLOW}1. Upstream firewall/router configuration${NC}"
    echo -e "${YELLOW}2. ISP or network provider filtering${NC}"
    echo -e "${YELLOW}3. Traefik service configuration${NC}"
    echo -e "${YELLOW}4. DNS records pointing to correct IP${NC}"
    echo ""
    
    echo -e "${BLUE}Test commands to run:${NC}"
    echo -e "${YELLOW}# From external network:${NC}"
    echo -e "${YELLOW}curl -I http://$METALLB_FIRST_IP${NC}"
    echo -e "${YELLOW}curl -I https://$METALLB_FIRST_IP${NC}"
    echo ""
    
    echo -e "${YELLOW}# Check Traefik logs:${NC}"
    echo -e "${YELLOW}kubectl logs -n kube-system deployment/traefik --tail=20${NC}"
    echo ""
    
    echo -e "${YELLOW}# Check MetalLB speaker logs:${NC}"
    echo -e "${YELLOW}kubectl logs -n metallb-system -l component=speaker --tail=10${NC}"
    echo ""
}

# Function to show summary
show_summary() {
    echo -e "${BLUE}Proxmox Firewall Configuration Summary${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    echo -e "${GREEN}✅ COMPLETED TASKS:${NC}"
    echo -e "${YELLOW}• Added HTTP (port 80) firewall rule${NC}"
    echo -e "${YELLOW}• Added HTTPS (port 443) firewall rule${NC}"
    echo -e "${YELLOW}• Added general MetalLB subnet rule${NC}"
    echo -e "${YELLOW}• Added return traffic rule${NC}"
    echo -e "${YELLOW}• Saved firewall configuration${NC}"
    echo ""
    echo -e "${BLUE}🔧 FIREWALL RULES ADDED:${NC}"
    echo -e "${YELLOW}• FORWARD -d $METALLB_SUBNET -p tcp --dport 80 -j ACCEPT${NC}"
    echo -e "${YELLOW}• FORWARD -d $METALLB_SUBNET -p tcp --dport 443 -j ACCEPT${NC}"
    echo -e "${YELLOW}• FORWARD -d $METALLB_SUBNET -j ACCEPT${NC}"
    echo -e "${YELLOW}• FORWARD -s $METALLB_SUBNET -j ACCEPT${NC}"
    echo ""
    echo -e "${BLUE}📋 NEXT STEPS:${NC}"
    echo -e "${YELLOW}1. Test external HTTP access: curl -I http://$METALLB_FIRST_IP${NC}"
    echo -e "${YELLOW}2. Test external HTTPS access: curl -I https://$METALLB_FIRST_IP${NC}"
    echo -e "${YELLOW}3. Update DNS records if not done already${NC}"
    echo -e "${YELLOW}4. Monitor Traefik and MetalLB logs${NC}"
    echo ""
    echo -e "${GREEN}🎉 Proxmox firewall configured for MetalLB!${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting Proxmox firewall configuration for MetalLB...${NC}"
    echo ""
    
    # Check environment
    check_environment
    echo ""
    
    # Show current firewall status
    show_current_firewall
    
    # Add firewall rules
    add_firewall_rules
    
    # Save firewall rules
    save_firewall_rules
    
    # Test firewall configuration
    test_firewall_config
    
    # Show troubleshooting info
    show_troubleshooting
    
    # Show summary
    show_summary
}

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Configure Proxmox firewall for MetalLB subnet access"
    echo ""
    echo "This script adds iptables rules to allow HTTP/HTTPS traffic"
    echo "to the MetalLB subnet (10.0.2.8/29)"
    echo ""
    echo "Environment Variables:"
    echo "  PROXMOX_HOST   SSH connection for remote Proxmox host"
    echo "                 Example: root@proxmox-ip"
    echo ""
    echo "Examples:"
    echo "  # Run on Proxmox host:"
    echo "  $0"
    echo ""
    echo "  # Run remotely:"
    echo "  PROXMOX_HOST=root@proxmox-ip $0"
    exit 0
fi

# Run main function
main "$@"
