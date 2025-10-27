#!/bin/bash

# Configure Proxmox Network for MetalLB Subnet
# Configures 10.0.2.8/29 subnet routing on Proxmox host

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
METALLB_SUBNET="10.0.2.8/29"
METALLB_NETWORK="10.0.2.8"
METALLB_FIRST_IP="10.0.2.9"
PUBLIC_BRIDGE="vmbr1"
PROXMOX_HOST="${PROXMOX_HOST:-}"

echo -e "${BLUE}Proxmox MetalLB Subnet Configuration${NC}"
echo -e "${BLUE}===================================${NC}"

# Function to check if running on Proxmox
check_proxmox_host() {
    if [ -z "$PROXMOX_HOST" ]; then
        echo -e "${YELLOW}PROXMOX_HOST not set. Checking if running on Proxmox host...${NC}"
        
        if [ -f "/etc/pve/local/pve-ssl.pem" ] || [ -d "/etc/pve" ]; then
            echo -e "${GREEN}✓ Running on Proxmox host${NC}"
            return 0
        else
            echo -e "${RED}✗ Not running on Proxmox host${NC}"
            echo -e "${YELLOW}Please run this script on the Proxmox host or set PROXMOX_HOST variable${NC}"
            echo -e "${YELLOW}Example: PROXMOX_HOST=root@your-proxmox-ip ./configure-proxmox-metallb-subnet.sh${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}Will configure Proxmox host: $PROXMOX_HOST${NC}"
        return 0
    fi
}

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

# Function to check current network configuration
check_current_config() {
    echo -e "${YELLOW}Checking current network configuration...${NC}"
    
    echo -e "${BLUE}Current bridge configuration:${NC}"
    execute_cmd "ip addr show $PUBLIC_BRIDGE" "Showing bridge $PUBLIC_BRIDGE"
    
    echo -e "${BLUE}Current routing table:${NC}"
    execute_cmd "ip route show | grep -E '(198\.55\.108|$PUBLIC_BRIDGE)' || echo 'No MetalLB routes found'" "Checking routes"
    
    echo -e "${BLUE}Testing connectivity to MetalLB subnet:${NC}"
    execute_cmd "ping -c 1 -W 2 $METALLB_FIRST_IP 2>/dev/null && echo 'MetalLB IP reachable' || echo 'MetalLB IP not reachable'" "Testing connectivity"
}

# Function to configure routing
configure_routing() {
    echo -e "${YELLOW}Configuring MetalLB subnet routing...${NC}"
    
    # Check if route already exists
    local route_exists
    route_exists=$(execute_cmd "ip route show | grep '$METALLB_SUBNET' || echo 'not_found'" "Checking existing routes")
    
    if [[ "$route_exists" == *"not_found"* ]]; then
        echo -e "${BLUE}Adding route for MetalLB subnet...${NC}"
        execute_cmd "ip route add $METALLB_SUBNET dev $PUBLIC_BRIDGE" "Adding MetalLB route"
        
        # Test the route
        execute_cmd "ping -c 1 -W 2 $METALLB_FIRST_IP && echo 'Route working' || echo 'Route test failed'" "Testing new route"
        
        echo -e "${GREEN}✓ Route added successfully${NC}"
    else
        echo -e "${GREEN}✓ Route already exists: $route_exists${NC}"
    fi
}

# Function to make routing permanent
make_routing_permanent() {
    echo -e "${YELLOW}Making routing configuration permanent...${NC}"
    
    # Check if already configured in interfaces file
    local interfaces_configured
    interfaces_configured=$(execute_cmd "grep -q '$METALLB_SUBNET' /etc/network/interfaces && echo 'configured' || echo 'not_configured'" "Checking interfaces file")
    
    if [[ "$interfaces_configured" == "not_configured" ]]; then
        echo -e "${BLUE}Adding permanent routing to /etc/network/interfaces...${NC}"
        
        # Create backup
        execute_cmd "cp /etc/network/interfaces /etc/network/interfaces.backup-\$(date +%Y%m%d-%H%M%S)" "Creating backup"
        
        # Add routing configuration
        execute_cmd "cat >> /etc/network/interfaces << 'EOF'

# MetalLB subnet routing
up ip route add $METALLB_SUBNET dev $PUBLIC_BRIDGE
down ip route del $METALLB_SUBNET dev $PUBLIC_BRIDGE
EOF" "Adding permanent routing"
        
        echo -e "${GREEN}✓ Permanent routing configuration added${NC}"
    else
        echo -e "${GREEN}✓ Permanent routing already configured${NC}"
    fi
}

# Function to configure firewall
configure_firewall() {
    echo -e "${YELLOW}Configuring firewall for MetalLB subnet...${NC}"
    
    # Check if iptables rules exist
    local fw_rules_exist
    fw_rules_exist=$(execute_cmd "iptables -L FORWARD | grep '$METALLB_NETWORK' && echo 'exists' || echo 'not_exists'" "Checking firewall rules")
    
    if [[ "$fw_rules_exist" == "not_exists" ]]; then
        echo -e "${BLUE}Adding firewall rules for MetalLB subnet...${NC}"
        
        # Add rules for HTTP/HTTPS
        execute_cmd "iptables -I FORWARD -d $METALLB_SUBNET -p tcp --dport 80 -j ACCEPT" "Adding HTTP rule"
        execute_cmd "iptables -I FORWARD -d $METALLB_SUBNET -p tcp --dport 443 -j ACCEPT" "Adding HTTPS rule"
        
        # Add general rule for MetalLB subnet
        execute_cmd "iptables -I FORWARD -d $METALLB_SUBNET -j ACCEPT" "Adding general MetalLB rule"
        
        echo -e "${GREEN}✓ Firewall rules added${NC}"
        
        # Save iptables rules
        echo -e "${BLUE}Saving iptables rules...${NC}"
        execute_cmd "iptables-save > /etc/iptables/rules.v4 2>/dev/null || netfilter-persistent save 2>/dev/null || echo 'Manual iptables save required'" "Saving iptables"
        
    else
        echo -e "${GREEN}✓ Firewall rules already exist${NC}"
    fi
}

# Function to enable proxy ARP if needed
configure_proxy_arp() {
    echo -e "${YELLOW}Configuring proxy ARP for MetalLB subnet...${NC}"
    
    # Check current proxy ARP setting
    local proxy_arp_enabled
    proxy_arp_enabled=$(execute_cmd "cat /proc/sys/net/ipv4/conf/$PUBLIC_BRIDGE/proxy_arp" "Checking proxy ARP")
    
    if [[ "$proxy_arp_enabled" != "1" ]]; then
        echo -e "${BLUE}Enabling proxy ARP...${NC}"
        execute_cmd "echo 1 > /proc/sys/net/ipv4/conf/$PUBLIC_BRIDGE/proxy_arp" "Enabling proxy ARP"
        
        # Make permanent
        execute_cmd "echo 'net.ipv4.conf.$PUBLIC_BRIDGE.proxy_arp = 1' >> /etc/sysctl.conf" "Making proxy ARP permanent"
        
        echo -e "${GREEN}✓ Proxy ARP enabled${NC}"
    else
        echo -e "${GREEN}✓ Proxy ARP already enabled${NC}"
    fi
}

# Function to test configuration
test_configuration() {
    echo -e "${YELLOW}Testing MetalLB subnet configuration...${NC}"
    
    echo -e "${BLUE}1. Testing routing:${NC}"
    execute_cmd "ip route get $METALLB_FIRST_IP" "Route lookup test"
    
    echo -e "${BLUE}2. Testing connectivity:${NC}"
    execute_cmd "ping -c 3 -W 2 $METALLB_FIRST_IP && echo 'Connectivity OK' || echo 'Connectivity FAILED'" "Ping test"
    
    echo -e "${BLUE}3. Testing HTTP connectivity:${NC}"
    execute_cmd "curl -I --connect-timeout 5 http://$METALLB_FIRST_IP 2>/dev/null | head -1 || echo 'HTTP test failed (expected if no service running)'" "HTTP test"
    
    echo -e "${BLUE}4. Checking firewall rules:${NC}"
    execute_cmd "iptables -L FORWARD | grep -A 2 -B 2 '$METALLB_NETWORK' || echo 'No specific firewall rules found'" "Firewall check"
}

# Function to show configuration summary
show_summary() {
    echo -e "${YELLOW}Configuration Summary:${NC}"
    echo ""
    echo -e "${BLUE}MetalLB Subnet Configuration:${NC}"
    echo -e "${GREEN}• Subnet: $METALLB_SUBNET${NC}"
    echo -e "${GREEN}• Bridge: $PUBLIC_BRIDGE${NC}"
    echo -e "${GREEN}• First IP: $METALLB_FIRST_IP${NC}"
    echo -e "${GREEN}• Available IPs: 10.0.2.9-14 (6 total)${NC}"
    echo ""
    echo -e "${BLUE}Configuration Applied:${NC}"
    echo -e "${GREEN}✓ Network routing configured${NC}"
    echo -e "${GREEN}✓ Firewall rules added${NC}"
    echo -e "${GREEN}✓ Proxy ARP enabled${NC}"
    echo -e "${GREEN}✓ Configuration made permanent${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "${YELLOW}1. Test external connectivity to MetalLB IPs${NC}"
    echo -e "${YELLOW}2. Update DNS records to point to new IPs${NC}"
    echo -e "${YELLOW}3. Monitor MetalLB speaker logs for announcements${NC}"
    echo -e "${YELLOW}4. Verify LoadBalancer services get IPs from new subnet${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting Proxmox MetalLB subnet configuration...${NC}"
    echo ""
    
    # Check if we're on Proxmox or need remote access
    if ! check_proxmox_host; then
        exit 1
    fi
    
    # Show current configuration
    check_current_config
    echo ""
    
    # Configure routing
    configure_routing
    echo ""
    
    # Make routing permanent
    make_routing_permanent
    echo ""
    
    # Configure firewall
    configure_firewall
    echo ""
    
    # Configure proxy ARP
    configure_proxy_arp
    echo ""
    
    # Test configuration
    test_configuration
    echo ""
    
    # Show summary
    show_summary
    
    echo ""
    echo -e "${GREEN}Proxmox MetalLB subnet configuration completed!${NC}"
}

# Show usage if help requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Configure Proxmox network for MetalLB subnet 10.0.2.8/29"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROXMOX_HOST   SSH connection string for remote Proxmox host"
    echo "                 Example: root@192.168.1.100"
    echo ""
    echo "Examples:"
    echo "  # Run on Proxmox host directly:"
    echo "  $0"
    echo ""
    echo "  # Run remotely:"
    echo "  PROXMOX_HOST=root@proxmox-ip $0"
    exit 0
fi

# Run main function
main "$@"
