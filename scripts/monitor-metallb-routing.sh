#!/bin/bash

# Monitor MetalLB Routing Configuration
# Tracks the status before, during, and after Proxmox routing configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

METALLB_IP="10.0.2.9"
METALLB_SUBNET="10.0.2.8/29"
LOG_FILE="/tmp/metallb-routing-monitor-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}MetalLB Routing Configuration Monitor${NC}"
echo -e "${BLUE}====================================${NC}"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check Kubernetes MetalLB status
check_k8s_metallb_status() {
    echo -e "${YELLOW}Checking Kubernetes MetalLB Status...${NC}"
    log_with_timestamp "=== Kubernetes MetalLB Status Check ==="
    
    echo -e "${BLUE}MetalLB IP Pools:${NC}"
    kubectl get ipaddresspool -n metallb-system 2>&1 | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}MetalLB L2 Advertisements:${NC}"
    kubectl get l2advertisement -n metallb-system 2>&1 | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}Traefik LoadBalancer Service:${NC}"
    kubectl get svc traefik -n kube-system 2>&1 | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}MetalLB Speaker Pods:${NC}"
    kubectl get pods -n metallb-system -l component=speaker 2>&1 | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}Recent MetalLB Speaker Logs:${NC}"
    kubectl logs -n metallb-system -l component=speaker --tail=10 2>&1 | tee -a "$LOG_FILE" || echo "No speaker logs available" | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to test connectivity from current location
test_current_connectivity() {
    echo -e "${YELLOW}Testing Current Connectivity to MetalLB IP...${NC}"
    log_with_timestamp "=== Current Connectivity Test ==="
    
    echo -e "${BLUE}Testing ping to $METALLB_IP:${NC}"
    if ping -c 3 -W 2 "$METALLB_IP" 2>&1 | tee -a "$LOG_FILE"; then
        echo -e "${GREEN}✓ Ping successful${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}✗ Ping failed (expected before Proxmox config)${NC}" | tee -a "$LOG_FILE"
    fi
    
    echo -e "${BLUE}Testing HTTP to $METALLB_IP:${NC}"
    if curl -I --connect-timeout 5 "http://$METALLB_IP" 2>&1 | tee -a "$LOG_FILE"; then
        echo -e "${GREEN}✓ HTTP successful${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}✗ HTTP failed (expected before Proxmox config)${NC}" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to show network route information
show_local_routing() {
    echo -e "${YELLOW}Local Network Routing Information...${NC}"
    log_with_timestamp "=== Local Network Routing ==="
    
    echo -e "${BLUE}Local IP addresses:${NC}"
    ip addr show 2>&1 | grep -E "(inet |UP)" | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}Local routing table:${NC}"
    ip route show 2>&1 | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}DNS resolution test:${NC}"
    nslookup kampfzwerg.gray-beard.com 2>&1 | tee -a "$LOG_FILE" || echo "DNS lookup failed" | tee -a "$LOG_FILE"
    nslookup ethos.gray-beard.com 2>&1 | tee -a "$LOG_FILE" || echo "DNS lookup failed" | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to monitor MetalLB speaker announcements
monitor_metallb_announcements() {
    echo -e "${YELLOW}Monitoring MetalLB Speaker Announcements...${NC}"
    log_with_timestamp "=== MetalLB Speaker Announcements ==="
    
    echo -e "${BLUE}Checking for IP announcement logs:${NC}"
    kubectl logs -n metallb-system -l component=speaker --since=5m 2>&1 | grep -i "announce\|ip\|traefik" | tee -a "$LOG_FILE" || echo "No recent announcements found" | tee -a "$LOG_FILE"
    
    echo -e "${BLUE}MetalLB Controller Logs:${NC}"
    kubectl logs -n metallb-system -l component=controller --tail=5 2>&1 | tee -a "$LOG_FILE" || echo "No controller logs available" | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to show expected Proxmox configuration
show_proxmox_config_needed() {
    echo -e "${YELLOW}Required Proxmox Configuration:${NC}"
    log_with_timestamp "=== Required Proxmox Configuration ==="
    
    echo -e "${BLUE}Commands needed on Proxmox host:${NC}"
    cat << 'EOF' | tee -a "$LOG_FILE"
# 1. Add MetalLB route
ip route add 10.0.2.8/29 dev vmbr1

# 2. Make route permanent
echo "up ip route add 10.0.2.8/29 dev vmbr1" >> /etc/network/interfaces
echo "down ip route del 10.0.2.8/29 dev vmbr1" >> /etc/network/interfaces

# 3. Add firewall rules
iptables -I FORWARD -d 10.0.2.8/29 -p tcp --dport 80 -j ACCEPT
iptables -I FORWARD -d 10.0.2.8/29 -p tcp --dport 443 -j ACCEPT
iptables-save > /etc/iptables/rules.v4

# 4. Test connectivity
ping -c 3 10.0.2.9
curl -I http://10.0.2.9
EOF
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to continuously monitor (for post-configuration)
continuous_monitor() {
    local duration=${1:-60}
    echo -e "${YELLOW}Starting continuous monitoring for $duration seconds...${NC}"
    log_with_timestamp "=== Continuous Monitoring Started ==="
    
    local end_time=$(($(date +%s) + duration))
    
    while [ $(date +%s) -lt $end_time ]; do
        echo -e "${BLUE}[$(date '+%H:%M:%S')] Testing connectivity...${NC}"
        
        if ping -c 1 -W 2 "$METALLB_IP" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Ping successful at $(date '+%H:%M:%S')${NC}" | tee -a "$LOG_FILE"
            
            if curl -I --connect-timeout 3 "http://$METALLB_IP" >/dev/null 2>&1; then
                echo -e "${GREEN}🎉 HTTP SUCCESS! MetalLB routing is working at $(date '+%H:%M:%S')${NC}" | tee -a "$LOG_FILE"
                break
            fi
        else
            echo -e "${YELLOW}⏳ Still waiting for connectivity...${NC}"
        fi
        
        sleep 5
    done
    
    log_with_timestamp "=== Continuous Monitoring Ended ==="
}

# Main monitoring function
main() {
    log_with_timestamp "=== MetalLB Routing Monitor Started ==="
    
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    echo ""
    
    # Check Kubernetes MetalLB status
    check_k8s_metallb_status
    
    # Test current connectivity
    test_current_connectivity
    
    # Show local routing
    show_local_routing
    
    # Monitor MetalLB announcements
    monitor_metallb_announcements
    
    # Show required Proxmox configuration
    show_proxmox_config_needed
    
    echo -e "${BLUE}Pre-configuration monitoring complete.${NC}"
    echo -e "${YELLOW}Log saved to: $LOG_FILE${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "${YELLOW}1. Run Proxmox configuration: ./scripts/add-metallb-route-to-existing-bridge.sh${NC}"
    echo -e "${YELLOW}2. Monitor results: ./scripts/monitor-metallb-routing.sh --continuous${NC}"
    
    # If continuous monitoring requested
    if [[ "${1:-}" == "--continuous" ]]; then
        echo ""
        continuous_monitor 120
    fi
    
    log_with_timestamp "=== MetalLB Routing Monitor Completed ==="
}

# Show help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--continuous]"
    echo ""
    echo "Monitor MetalLB routing configuration status"
    echo ""
    echo "Options:"
    echo "  --continuous    Run continuous monitoring after initial check"
    echo "  -h, --help      Show this help"
    echo ""
    echo "This script:"
    echo "• Checks Kubernetes MetalLB configuration"
    echo "• Tests current connectivity to MetalLB IPs"
    echo "• Shows required Proxmox configuration"
    echo "• Monitors MetalLB speaker announcements"
    echo "• Logs all output with timestamps"
    exit 0
fi

# Run main function
main "$@"
