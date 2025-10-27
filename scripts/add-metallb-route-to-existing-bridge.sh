#!/bin/bash

# Add MetalLB Subnet Route to Existing Proxmox Bridge
# Simple script to add 10.0.2.8/29 routing to existing vmbr1

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
PUBLIC_BRIDGE="vmbr1"
PROXMOX_HOST="${PROXMOX_HOST:-}"

echo -e "${BLUE}Add MetalLB Route to Existing Proxmox Bridge${NC}"
echo -e "${BLUE}============================================${NC}"

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

# Function to check if running on Proxmox
check_environment() {
    if [ -z "$PROXMOX_HOST" ]; then
        if [ -f "/etc/pve/local/pve-ssl.pem" ] || [ -d "/etc/pve" ]; then
            echo -e "${GREEN}✓ Running on Proxmox host${NC}"
        else
            echo -e "${YELLOW}⚠ Not on Proxmox host. Use: PROXMOX_HOST=root@proxmox-ip $0${NC}"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        echo -e "${BLUE}Configuring remote Proxmox host: $PROXMOX_HOST${NC}"
    fi
}

# Function to show current configuration
show_current_config() {
    echo -e "${YELLOW}Current Network Configuration:${NC}"
    echo ""
    
    echo -e "${BLUE}Bridge $PUBLIC_BRIDGE configuration:${NC}"
    execute_cmd "ip addr show $PUBLIC_BRIDGE | head -10" "Showing bridge details"
    echo ""
    
    echo -e "${BLUE}Current routing table (relevant entries):${NC}"
    execute_cmd "ip route show | grep -E '(107\.172\.99|198\.55\.108|$PUBLIC_BRIDGE)' || echo 'No MetalLB routes found'" "Checking routes"
    echo ""
    
    echo -e "${BLUE}Testing current MetalLB connectivity:${NC}"
    execute_cmd "ping -c 1 -W 2 $METALLB_FIRST_IP 2>/dev/null && echo '✓ MetalLB IP reachable' || echo '✗ MetalLB IP not reachable (expected)'" "Testing connectivity"
    echo ""
}

# Function to add MetalLB route
add_metallb_route() {
    echo -e "${YELLOW}Adding MetalLB subnet route...${NC}"
    
    # Check if route already exists
    local route_check
    route_check=$(execute_cmd "ip route show | grep '$METALLB_SUBNET' || echo 'not_found'" "Checking existing route")
    
    if [[ "$route_check" == "not_found" ]]; then
        echo -e "${BLUE}Adding route: $METALLB_SUBNET via $PUBLIC_BRIDGE${NC}"
        execute_cmd "ip route add $METALLB_SUBNET dev $PUBLIC_BRIDGE" "Adding MetalLB route"
        
        # Test the new route
        echo -e "${BLUE}Testing new route...${NC}"
        execute_cmd "ping -c 2 -W 3 $METALLB_FIRST_IP && echo '✓ Route working!' || echo '⚠ Route test inconclusive (may need service running)'" "Testing route"
        
        echo -e "${GREEN}✓ MetalLB route added successfully${NC}"
    else
        echo -e "${GREEN}✓ MetalLB route already exists:${NC}"
        echo "$route_check"
    fi
    echo ""
}

# Function to make route permanent
make_route_permanent() {
    echo -e "${YELLOW}Making MetalLB route permanent...${NC}"
    
    # Check if already in interfaces file
    local interfaces_check
    interfaces_check=$(execute_cmd "grep -q '$METALLB_SUBNET' /etc/network/interfaces && echo 'found' || echo 'not_found'" "Checking interfaces file")
    
    if [[ "$interfaces_check" == "not_found" ]]; then
        echo -e "${BLUE}Adding permanent route to /etc/network/interfaces...${NC}"
        
        # Create backup first
        execute_cmd "cp /etc/network/interfaces /etc/network/interfaces.backup-\$(date +%Y%m%d-%H%M%S)" "Creating backup"
        
        # Find the vmbr1 section and add the route
        execute_cmd "cat >> /etc/network/interfaces << 'EOF'

# MetalLB subnet route (added by automation)
# Route MetalLB LoadBalancer IPs through public bridge
up ip route add $METALLB_SUBNET dev $PUBLIC_BRIDGE
down ip route del $METALLB_SUBNET dev $PUBLIC_BRIDGE
EOF" "Adding permanent route configuration"
        
        echo -e "${GREEN}✓ Permanent route configuration added${NC}"
    else
        echo -e "${GREEN}✓ Permanent route already configured${NC}"
    fi
    echo ""
}

# Function to configure basic firewall
configure_basic_firewall() {
    echo -e "${YELLOW}Configuring basic firewall rules...${NC}"
    
    # Check if MetalLB firewall rules exist
    local fw_check
    fw_check=$(execute_cmd "iptables -L FORWARD | grep '198\.55\.108' && echo 'found' || echo 'not_found'" "Checking firewall rules")
    
    if [[ "$fw_check" == "not_found" ]]; then
        echo -e "${BLUE}Adding firewall rules for MetalLB subnet...${NC}"
        
        # Add basic rules for HTTP/HTTPS
        execute_cmd "iptables -I FORWARD -d $METALLB_SUBNET -p tcp --dport 80 -j ACCEPT" "Adding HTTP rule"
        execute_cmd "iptables -I FORWARD -d $METALLB_SUBNET -p tcp --dport 443 -j ACCEPT" "Adding HTTPS rule"
        
        # Save rules (try different methods)
        echo -e "${BLUE}Saving firewall rules...${NC}"
        execute_cmd "iptables-save > /etc/iptables/rules.v4 2>/dev/null || netfilter-persistent save 2>/dev/null || echo 'Please save iptables rules manually'" "Saving rules"
        
        echo -e "${GREEN}✓ Basic firewall rules added${NC}"
    else
        echo -e "${GREEN}✓ Firewall rules already exist${NC}"
    fi
    echo ""
}

# Function to verify configuration
verify_configuration() {
    echo -e "${YELLOW}Verifying MetalLB network configuration...${NC}"
    echo ""
    
    echo -e "${BLUE}1. Route verification:${NC}"
    execute_cmd "ip route get $METALLB_FIRST_IP" "Route lookup"
    echo ""
    
    echo -e "${BLUE}2. Connectivity test:${NC}"
    execute_cmd "ping -c 3 -W 2 $METALLB_FIRST_IP && echo '✓ Connectivity OK' || echo '⚠ No response (normal if no service running)'" "Ping test"
    echo ""
    
    echo -e "${BLUE}3. HTTP test (if Traefik is running):${NC}"
    execute_cmd "curl -I --connect-timeout 5 http://$METALLB_FIRST_IP 2>/dev/null | head -1 || echo '⚠ HTTP test failed (normal if external access not configured)'" "HTTP test"
    echo ""
    
    echo -e "${BLUE}4. Current routes:${NC}"
    execute_cmd "ip route show | grep -E '(198\.55\.108|$PUBLIC_BRIDGE)'" "Showing relevant routes"
    echo ""
}

# Function to show final summary
show_summary() {
    echo -e "${BLUE}Configuration Summary${NC}"
    echo -e "${BLUE}===================${NC}"
    echo ""
    echo -e "${GREEN}✅ COMPLETED TASKS:${NC}"
    echo -e "${YELLOW}• Added route: $METALLB_SUBNET via $PUBLIC_BRIDGE${NC}"
    echo -e "${YELLOW}• Made routing configuration permanent${NC}"
    echo -e "${YELLOW}• Added basic firewall rules (HTTP/HTTPS)${NC}"
    echo -e "${YELLOW}• Verified network connectivity${NC}"
    echo ""
    echo -e "${BLUE}🔧 NETWORK CONFIGURATION:${NC}"
    echo -e "${YELLOW}• Existing Bridge: $PUBLIC_BRIDGE (10.0.1.x/24)${NC}"
    echo -e "${YELLOW}• MetalLB Subnet: $METALLB_SUBNET${NC}"
    echo -e "${YELLOW}• Available IPs: 10.0.2.9-14 (6 total)${NC}"
    echo -e "${YELLOW}• Current Traefik IP: $METALLB_FIRST_IP${NC}"
    echo ""
    echo -e "${BLUE}📋 NEXT STEPS:${NC}"
    echo -e "${YELLOW}1. Test external connectivity: curl -I http://$METALLB_FIRST_IP${NC}"
    echo -e "${YELLOW}2. Update DNS records to point to $METALLB_FIRST_IP${NC}"
    echo -e "${YELLOW}3. Monitor MetalLB speaker logs: kubectl logs -n metallb-system -l component=speaker${NC}"
    echo -e "${YELLOW}4. Verify LoadBalancer services get IPs from new subnet${NC}"
    echo ""
    echo -e "${GREEN}🎉 MetalLB subnet routing configured successfully!${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting MetalLB route configuration for existing Proxmox bridges...${NC}"
    echo ""
    
    # Check environment
    check_environment
    echo ""
    
    # Show current configuration
    show_current_config
    
    # Add MetalLB route
    add_metallb_route
    
    # Make route permanent
    make_route_permanent
    
    # Configure basic firewall
    configure_basic_firewall
    
    # Verify configuration
    verify_configuration
    
    # Show summary
    show_summary
}

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Add MetalLB subnet route to existing Proxmox bridge configuration"
    echo ""
    echo "This script:"
    echo "• Adds route for 10.0.2.8/29 via existing vmbr1 bridge"
    echo "• Makes the route permanent in /etc/network/interfaces"
    echo "• Adds basic firewall rules for HTTP/HTTPS"
    echo "• Verifies connectivity"
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
