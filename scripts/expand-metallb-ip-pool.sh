#!/bin/bash

# Expand MetalLB IP Pool Script
# Provides multiple options to rectify single IP configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}MetalLB IP Pool Expansion Options${NC}"
echo -e "${BLUE}=================================${NC}"

# Function to show current configuration
show_current_config() {
    echo -e "${YELLOW}Current MetalLB Configuration:${NC}"
    kubectl get ipaddresspool -n metallb-system -o yaml | grep -A 5 "addresses:"
    echo ""
    
    echo -e "${YELLOW}Current LoadBalancer Services:${NC}"
    kubectl get svc --all-namespaces | grep LoadBalancer
    echo ""
}

# Function to create IP range configuration
create_ip_range_config() {
    echo -e "${YELLOW}Option 1: IP Range Configuration${NC}"
    
    cat > /tmp/metallb-ip-range.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.214-10.0.1.220  # Range of 7 IPs
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

    echo -e "${BLUE}IP Range: 10.0.1.214-220 (7 IPs total)${NC}"
    echo -e "${GREEN}✓ Provides multiple IPs for different services${NC}"
    echo -e "${GREEN}✓ Automatic failover if one IP becomes unavailable${NC}"
    echo -e "${GREEN}✓ Supports multiple LoadBalancer services${NC}"
}

# Function to create multiple pool configuration
create_multiple_pools_config() {
    echo -e "${YELLOW}Option 2: Multiple IP Pools Configuration${NC}"
    
    cat > /tmp/metallb-multiple-pools.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: web-services-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.214/32
  - 10.0.1.215/32
  - 10.0.1.216/32
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: internal-services-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.217/32
  - 10.0.1.218/32
  autoAssign: false  # Manual assignment
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: web-services-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - web-services-pool
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: internal-services-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - internal-services-pool
EOF

    echo -e "${BLUE}Web Services Pool: 10.0.1.214-216 (3 IPs, auto-assign)${NC}"
    echo -e "${BLUE}Internal Services Pool: 10.0.1.217-218 (2 IPs, manual)${NC}"
    echo -e "${GREEN}✓ Separates public and internal services${NC}"
    echo -e "${GREEN}✓ Different assignment policies per pool${NC}"
    echo -e "${GREEN}✓ Better resource organization${NC}"
}

# Function to create high availability configuration
create_ha_config() {
    echo -e "${YELLOW}Option 3: High Availability Configuration${NC}"
    
    cat > /tmp/metallb-ha-config.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: primary-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.214-10.0.1.216  # Primary range
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: backup-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.217-10.0.1.219  # Backup range
  autoAssign: false  # Only used when primary is exhausted
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: primary-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - primary-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/arch: amd64  # All nodes
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: backup-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - backup-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/arch: amd64
EOF

    echo -e "${BLUE}Primary Pool: 10.0.1.214-216 (auto-assign)${NC}"
    echo -e "${BLUE}Backup Pool: 10.0.1.217-219 (manual failover)${NC}"
    echo -e "${GREEN}✓ Dedicated primary and backup IP ranges${NC}"
    echo -e "${GREEN}✓ Automatic primary pool usage${NC}"
    echo -e "${GREEN}✓ Manual backup pool for emergencies${NC}"
}

# Function to create node-specific configuration
create_node_specific_config() {
    echo -e "${YELLOW}Option 4: Node-Specific IP Assignment${NC}"
    
    cat > /tmp/metallb-node-specific.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gimli-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.214/32
  - 10.0.1.215/32
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: legolas-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.216/32
  - 10.0.1.217/32
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: aragorn-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.218/32
  - 10.0.1.219/32
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: gimli-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - gimli-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: gimli
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: legolas-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - legolas-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: legolas
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: aragorn-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - aragorn-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: aragorn
EOF

    echo -e "${BLUE}Gimli (Control): 10.0.1.214-215${NC}"
    echo -e "${BLUE}Legolas (Worker): 10.0.1.216-217${NC}"
    echo -e "${BLUE}Aragorn (Worker): 10.0.1.218-219${NC}"
    echo -e "${GREEN}✓ Node-specific IP assignments${NC}"
    echo -e "${GREEN}✓ Distributes load across nodes${NC}"
    echo -e "${GREEN}✓ Node failure isolation${NC}"
}

# Function to apply selected configuration
apply_configuration() {
    local config_file=$1
    local option_name=$2
    
    echo -e "${YELLOW}Applying $option_name...${NC}"
    
    # Backup current configuration
    kubectl get ipaddresspool -n metallb-system -o yaml > /tmp/metallb-backup-$(date +%Y%m%d-%H%M%S).yaml
    kubectl get l2advertisement -n metallb-system -o yaml >> /tmp/metallb-backup-$(date +%Y%m%d-%H%M%S).yaml
    
    # Apply new configuration
    kubectl apply -f "$config_file"
    
    # Wait for MetalLB to process changes
    echo -e "${BLUE}Waiting for MetalLB to process changes...${NC}"
    sleep 10
    
    # Restart MetalLB components to ensure they pick up changes
    kubectl rollout restart deployment/metallb-controller -n metallb-system
    kubectl rollout restart daemonset/metallb-speaker -n metallb-system
    
    # Wait for rollout
    kubectl rollout status deployment/metallb-controller -n metallb-system --timeout=60s
    kubectl rollout status daemonset/metallb-speaker -n metallb-system --timeout=60s
    
    echo -e "${GREEN}✓ Configuration applied successfully${NC}"
    
    # Show new configuration
    echo -e "${BLUE}New IP Address Pools:${NC}"
    kubectl get ipaddresspool -n metallb-system
    
    echo -e "${BLUE}New L2 Advertisements:${NC}"
    kubectl get l2advertisement -n metallb-system
    
    # Clean up temp file
    rm -f "$config_file"
}

# Function to show recommendations
show_recommendations() {
    echo -e "${YELLOW}Recommendations:${NC}"
    echo ""
    echo -e "${BLUE}For your current setup, I recommend:${NC}"
    echo ""
    echo -e "${GREEN}1. Option 1 (IP Range) - Best for simplicity${NC}"
    echo -e "${YELLOW}   • Easy to manage${NC}"
    echo -e "${YELLOW}   • Provides 7 IPs for growth${NC}"
    echo -e "${YELLOW}   • Automatic failover${NC}"
    echo ""
    echo -e "${GREEN}2. Option 2 (Multiple Pools) - Best for organization${NC}"
    echo -e "${YELLOW}   • Separates web and internal services${NC}"
    echo -e "${YELLOW}   • Better resource control${NC}"
    echo -e "${YELLOW}   • Flexible assignment policies${NC}"
    echo ""
    echo -e "${RED}Important Notes:${NC}"
    echo -e "${YELLOW}• Ensure all IPs (214-220) are available in your network${NC}"
    echo -e "${YELLOW}• Check with network admin about IP range allocation${NC}"
    echo -e "${YELLOW}• Test connectivity for each new IP before production use${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting MetalLB IP pool expansion analysis...${NC}"
    echo ""
    
    # Show current configuration
    show_current_config
    
    # Show all options
    create_ip_range_config
    echo ""
    
    create_multiple_pools_config
    echo ""
    
    create_ha_config
    echo ""
    
    create_node_specific_config
    echo ""
    
    # Show recommendations
    show_recommendations
    echo ""
    
    # Ask user which option to apply
    echo -e "${YELLOW}Which configuration would you like to apply?${NC}"
    echo "1. IP Range (10.0.1.214-220)"
    echo "2. Multiple Pools (Web + Internal)"
    echo "3. High Availability (Primary + Backup)"
    echo "4. Node-Specific Assignment"
    echo "5. Show configurations only (no changes)"
    echo ""
    echo -n "Enter choice (1-5): "
    read -r choice
    
    case $choice in
        1)
            apply_configuration "/tmp/metallb-ip-range.yaml" "IP Range Configuration"
            ;;
        2)
            apply_configuration "/tmp/metallb-multiple-pools.yaml" "Multiple Pools Configuration"
            ;;
        3)
            apply_configuration "/tmp/metallb-ha-config.yaml" "High Availability Configuration"
            ;;
        4)
            apply_configuration "/tmp/metallb-node-specific.yaml" "Node-Specific Configuration"
            ;;
        5)
            echo -e "${GREEN}Configuration files created in /tmp/ for review${NC}"
            echo -e "${YELLOW}Files created:${NC}"
            ls -la /tmp/metallb-*.yaml
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}MetalLB IP pool expansion completed!${NC}"
}

# Run main function
main "$@"
