#!/bin/bash

# Fix External Connectivity to Traefik via MetalLB
# This script configures firewall rules to allow HTTP/HTTPS traffic
# to the MetalLB subnet (10.0.2.8/29)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
METALLB_SUBNET="10.0.2.8/29"
TRAEFIK_IP="10.0.2.9"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Fix External Traefik Connectivity           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Function to check if running as root
checkRoot() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}✗ This script must be run as root${NC}"
        echo -e "${YELLOW}  Please run: sudo $0${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Running as root${NC}"
}

# Function to check environment
checkEnvironment() {
    echo -e "${BLUE}Checking environment...${NC}"
    
    # Check if iptables is available
    if command -v iptables >/dev/null 2>&1; then
        echo -e "${GREEN}✓ iptables is available${NC}"
    else
        echo -e "${RED}✗ iptables not found${NC}"
        exit 1
    fi
    
    # Check if this looks like the gateway/firewall
    if ip route | grep -q "default"; then
        echo -e "${GREEN}✓ Default route configured${NC}"
    fi
    echo ""
}

# Function to show current status
showCurrentStatus() {
    echo -e "${YELLOW}═══ Current Configuration ═══${NC}"
    echo ""
    
    echo -e "${BLUE}Current FORWARD chain policy:${NC}"
    iptables -L FORWARD -n | head -3
    echo ""
    
    echo -e "${BLUE}Existing MetalLB rules:${NC}"
    if iptables -L FORWARD -n | grep -q "198\.55\.108"; then
        iptables -L FORWARD -n --line-numbers | grep "198\.55\.108"
    else
        echo -e "${YELLOW}No existing MetalLB rules found${NC}"
    fi
    echo ""
    
    echo -e "${BLUE}Testing connectivity:${NC}"
    if ping -c 2 -W 2 $TRAEFIK_IP >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Ping to $TRAEFIK_IP: SUCCESS${NC}"
    else
        echo -e "${RED}✗ Ping to $TRAEFIK_IP: FAILED${NC}"
    fi
    
    if timeout 5 curl -s -I http://$TRAEFIK_IP >/dev/null 2>&1; then
        echo -e "${GREEN}✓ HTTP to $TRAEFIK_IP: SUCCESS${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP to $TRAEFIK_IP: TIMEOUT/BLOCKED${NC}"
    fi
    echo ""
}

# Function to add firewall rules
addFirewallRules() {
    echo -e "${YELLOW}═══ Adding Firewall Rules ═══${NC}"
    echo ""
    
    # Check if rules already exist
    local existingRules
    existingRules=$(iptables -L FORWARD -n | grep -c "198\.55\.108" || echo "0")
    
    if [ "$existingRules" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found $existingRules existing MetalLB rules${NC}"
        read -p "Remove existing rules and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Removing existing rules...${NC}"
            # Remove all existing MetalLB rules
            while iptables -L FORWARD -n --line-numbers | grep "198\.55\.108" | head -1 | awk '{print $1}' | xargs -I {} iptables -D FORWARD {} 2>/dev/null; do
                echo -e "${YELLOW}  Removed rule{}${NC}"
            done
            echo -e "${GREEN}✓ Existing rules removed${NC}"
        fi
    fi
    
    echo -e "${BLUE}Adding new firewall rules...${NC}"
    
    # Add rules for HTTP and HTTPS (specific ports)
    iptables -I FORWARD 1 -d $METALLB_SUBNET -p tcp --dport 80 -j ACCEPT
    echo -e "${GREEN}✓ Added HTTP (port 80) rule${NC}"
    
    iptables -I FORWARD 1 -d $METALLB_SUBNET -p tcp --dport 443 -j ACCEPT
    echo -e "${GREEN}✓ Added HTTPS (port 443) rule${NC}"
    
    # Add general rule for MetalLB subnet
    iptables -I FORWARD 1 -d $METALLB_SUBNET -j ACCEPT
    echo -e "${GREEN}✓ Added general MetalLB subnet rule${NC}"
    
    # Add rule for return traffic
    iptables -I FORWARD 1 -s $METALLB_SUBNET -j ACCEPT
    echo -e "${GREEN}✓ Added return traffic rule${NC}"
    
    echo ""
}

# Function to save firewall rules
saveFirewallRules() {
    echo -e "${YELLOW}═══ Saving Firewall Rules ═══${NC}"
    echo ""
    
    # Create iptables directory
    mkdir -p /etc/iptables
    
    # Try different methods to save rules
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4
        echo -e "${GREEN}✓ Rules saved to /etc/iptables/rules.v4${NC}"
        
        # Try to ensure rules persist on reboot
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save
            echo -e "${GREEN}✓ Rules saved with netfilter-persistent${NC}"
        elif [ -f /etc/network/if-pre-up.d/iptables ]; then
            echo "#!/bin/sh" > /etc/network/if-pre-up.d/iptables
            echo "/sbin/iptables-restore < /etc/iptables/rules.v4" >> /etc/network/if-pre-up.d/iptables
            chmod +x /etc/network/if-pre-up.d/iptables
            echo -e "${GREEN}✓ Created if-pre-up.d/iptables script${NC}"
        fi
    else
        echo -e "${RED}✗ iptables-save not found${NC}"
        echo -e "${YELLOW}⚠ Rules will NOT persist across reboots${NC}"
    fi
    echo ""
}

# Function to test configuration
testConfiguration() {
    echo -e "${YELLOW}═══ Testing Configuration ═══${NC}"
    echo ""
    
    echo -e "${BLUE}1. Checking new firewall rules:${NC}"
    iptables -L FORWARD -n --line-numbers | grep "198\.55\.108" | head -10
    echo ""
    
    echo -e "${BLUE}2. Testing connectivity:${NC}"
    if ping -c 3 -W 2 $TRAEFIK_IP >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Ping: SUCCESS${NC}"
    else
        echo -e "${RED}✗ Ping: FAILED${NC}"
    fi
    
    if timeout 10 curl -s -I http://$TRAEFIK_IP | head -1 | grep -q "HTTP"; then
        echo -e "${GREEN}✓ HTTP: SUCCESS${NC}"
        echo -e "${BLUE}  Response: $(timeout 10 curl -s -I http://$TRAEFIK_IP | head -1)${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP: Still blocked or no service${NC}"
    fi
    
    if timeout 10 curl -s -I -k https://$TRAEFIK_IP 2>/dev/null | head -1 | grep -q "HTTP"; then
        echo -e "${GREEN}✓ HTTPS: SUCCESS${NC}"
    else
        echo -e "${YELLOW}⚠ HTTPS: Still blocked or no service${NC}"
    fi
    echo ""
}

# Function to show summary
showSummary() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Summary                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✅ Firewall rules added:${NC}"
    echo -e "${YELLOW}   • HTTP (port 80) to $METALLB_SUBNET${NC}"
    echo -e "${YELLOW}   • HTTPS (port 443) to $METALLB_SUBNET${NC}"
    echo -e "${YELLOW}   • General traffic to $METALLB_SUBNET${NC}"
    echo -e "${YELLOW}   • Return traffic from $METALLB_SUBNET${NC}"
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo -e "${YELLOW}1. Test from external network:${NC}"
    echo -e "   curl -I http://$TRAEFIK_IP"
    echo -e "   curl -I https://$TRAEFIK_IP"
    echo ""
    echo -e "${YELLOW}2. If still not working, check:${NC}"
    echo -e "   • Upstream firewall/router configuration"
    echo -e "   • ISP filtering"
    echo -e "   • DNS records"
    echo ""
    echo -e "${GREEN}🎉 Configuration complete!${NC}"
}

# Main execution
main() {
    checkRoot
    checkEnvironment
    showCurrentStatus
    addFirewallRules
    saveFirewallRules
    testConfiguration
    showSummary
}

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: sudo $0"
    echo ""
    echo "This script adds iptables firewall rules to allow HTTP/HTTPS traffic"
    echo "to the MetalLB subnet ($METALLB_SUBNET) for Traefik ingress."
    echo ""
    echo "Requirements:"
    echo "  • Must run as root"
    echo "  • Must run on the gateway/firewall host"
    echo ""
    echo "The script will:"
    echo "  1. Check current firewall configuration"
    echo "  2. Add FORWARD rules for HTTP/HTTPS to MetalLB subnet"
    echo "  3. Save rules to persist across reboots"
    echo "  4. Test connectivity"
    exit 0
fi

# Run main function
main "$@"


