#!/bin/bash

# Configure MetalLB with Dedicated 10.0.2.8/29 Subnet
# Migrates from single IP to dedicated subnet with proper redundancy

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}MetalLB Dedicated Subnet Configuration${NC}"
echo -e "${BLUE}=====================================${NC}"

# Subnet information
SUBNET="10.0.2.8/29"
NETWORK_ADDR="10.0.2.8"
BROADCAST_ADDR="10.0.2.15"
FIRST_USABLE="10.0.2.9"
LAST_USABLE="10.0.2.14"

# Function to show current configuration
show_current_config() {
    echo -e "${YELLOW}Current MetalLB Configuration:${NC}"
    echo -e "${BLUE}Current IP Pool:${NC}"
    kubectl get ipaddresspool -n metallb-system -o yaml | grep -A 3 "addresses:" || echo "No current pools found"
    
    echo -e "${BLUE}Current LoadBalancer Services:${NC}"
    kubectl get svc --all-namespaces | grep LoadBalancer || echo "No LoadBalancer services found"
    echo ""
}

# Function to create backup
create_backup() {
    echo -e "${YELLOW}Creating backup of current MetalLB configuration...${NC}"
    
    local backup_file="/tmp/metallb-backup-$(date +%Y%m%d-%H%M%S).yaml"
    
    {
        echo "# MetalLB Configuration Backup - $(date)"
        echo "# Original configuration before subnet migration"
        echo "---"
        kubectl get ipaddresspool -n metallb-system -o yaml
        echo "---"
        kubectl get l2advertisement -n metallb-system -o yaml
    } > "$backup_file"
    
    echo -e "${GREEN}✓ Backup saved to: $backup_file${NC}"
    echo ""
}

# Function to create single pool configuration
create_single_pool_config() {
    echo -e "${YELLOW}Option 1: Single Pool Configuration${NC}"
    
    cat > /tmp/metallb-single-pool-subnet.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: dedicated-subnet-pool
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
spec:
  addresses:
  - 10.0.2.9-10.0.2.14  # All 6 usable IPs
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: dedicated-subnet-l2
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
spec:
  ipAddressPools:
  - dedicated-subnet-pool
EOF

    echo -e "${BLUE}IP Range: 10.0.2.9-14 (6 IPs)${NC}"
    echo -e "${GREEN}✓ Simple single pool management${NC}"
    echo -e "${GREEN}✓ All 6 IPs available for any service${NC}"
    echo -e "${GREEN}✓ Automatic IP assignment${NC}"
    echo ""
}

# Function to create service-specific pools
create_service_specific_pools() {
    echo -e "${YELLOW}Option 2: Service-Specific Pools${NC}"
    
    cat > /tmp/metallb-service-pools-subnet.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: web-services-subnet
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
    pool-type: web-services
spec:
  addresses:
  - 10.0.2.9/32   # Primary web service (Traefik)
  - 10.0.2.10/32  # Secondary web service
  - 10.0.2.11/32  # Additional web service
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: internal-services-subnet
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
    pool-type: internal-services
spec:
  addresses:
  - 10.0.2.12/32  # Internal service 1
  - 10.0.2.13/32  # Internal service 2
  autoAssign: false   # Manual assignment for internal services
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: backup-services-subnet
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
    pool-type: backup
spec:
  addresses:
  - 10.0.2.14/32  # Emergency/backup IP
  autoAssign: false   # Manual assignment only
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: web-services-subnet-l2
  namespace: metallb-system
  labels:
    app: metallb
    pool-type: web-services
spec:
  ipAddressPools:
  - web-services-subnet
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: internal-services-subnet-l2
  namespace: metallb-system
  labels:
    app: metallb
    pool-type: internal-services
spec:
  ipAddressPools:
  - internal-services-subnet
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: backup-services-subnet-l2
  namespace: metallb-system
  labels:
    app: metallb
    pool-type: backup
spec:
  ipAddressPools:
  - backup-services-subnet
EOF

    echo -e "${BLUE}Web Services: 10.0.2.9-11 (3 IPs, auto-assign)${NC}"
    echo -e "${BLUE}Internal Services: 10.0.2.12-13 (2 IPs, manual)${NC}"
    echo -e "${BLUE}Backup/Emergency: 10.0.2.14 (1 IP, manual)${NC}"
    echo -e "${GREEN}✓ Service type separation${NC}"
    echo -e "${GREEN}✓ Different assignment policies${NC}"
    echo -e "${GREEN}✓ Reserved emergency IP${NC}"
    echo ""
}

# Function to create priority-based configuration
create_priority_config() {
    echo -e "${YELLOW}Option 3: Priority-Based Configuration${NC}"
    
    cat > /tmp/metallb-priority-subnet.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: primary-subnet-pool
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
    priority: primary
spec:
  addresses:
  - 10.0.2.9/32   # Primary IP (current Traefik)
  - 10.0.2.10/32  # Primary backup
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: secondary-subnet-pool
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
    priority: secondary
spec:
  addresses:
  - 10.0.2.11/32  # Secondary services
  - 10.0.2.12/32
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: reserve-subnet-pool
  namespace: metallb-system
  labels:
    app: metallb
    subnet: "198-55-108-8-29"
    priority: reserve
spec:
  addresses:
  - 10.0.2.13/32  # Reserve IPs
  - 10.0.2.14/32
  autoAssign: false   # Manual assignment only
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: primary-subnet-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - primary-subnet-pool
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: secondary-subnet-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - secondary-subnet-pool
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: reserve-subnet-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - reserve-subnet-pool
EOF

    echo -e "${BLUE}Primary Pool: 10.0.2.9-10 (2 IPs, auto)${NC}"
    echo -e "${BLUE}Secondary Pool: 10.0.2.11-12 (2 IPs, auto)${NC}"
    echo -e "${BLUE}Reserve Pool: 10.0.2.13-14 (2 IPs, manual)${NC}"
    echo -e "${GREEN}✓ Priority-based IP allocation${NC}"
    echo -e "${GREEN}✓ Graduated assignment policies${NC}"
    echo -e "${GREEN}✓ Reserved capacity for emergencies${NC}"
    echo ""
}

# Function to apply configuration
apply_configuration() {
    local config_file=$1
    local config_name=$2
    
    echo -e "${YELLOW}Applying $config_name...${NC}"
    
    # Apply new configuration
    kubectl apply -f "$config_file"
    
    echo -e "${BLUE}Waiting for MetalLB to process changes...${NC}"
    sleep 10
    
    # Restart MetalLB components
    echo -e "${BLUE}Restarting MetalLB components...${NC}"
    kubectl rollout restart deployment/metallb-controller -n metallb-system
    kubectl rollout restart daemonset/metallb-speaker -n metallb-system
    
    # Wait for rollout
    kubectl rollout status deployment/metallb-controller -n metallb-system --timeout=60s
    kubectl rollout status daemonset/metallb-speaker -n metallb-system --timeout=60s
    
    echo -e "${GREEN}✓ Configuration applied successfully${NC}"
    
    # Show new configuration
    echo -e "${BLUE}New IP Address Pools:${NC}"
    kubectl get ipaddresspool -n metallb-system
    echo ""
    
    echo -e "${BLUE}New L2 Advertisements:${NC}"
    kubectl get l2advertisement -n metallb-system
    echo ""
    
    # Check Traefik service
    echo -e "${BLUE}Traefik Service Status:${NC}"
    kubectl get svc traefik -n kube-system
    echo ""
    
    # Clean up temp file
    rm -f "$config_file"
}

# Function to test connectivity
test_new_ips() {
    echo -e "${YELLOW}Testing connectivity to new subnet IPs...${NC}"
    
    local traefik_ip=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -n "$traefik_ip" ]; then
        echo -e "${BLUE}Traefik assigned IP: $traefik_ip${NC}"
        
        if [[ "$traefik_ip" =~ ^198\.55\.108\.(9|1[0-4])$ ]]; then
            echo -e "${GREEN}✓ Traefik successfully assigned IP from new subnet${NC}"
            
            # Test connectivity
            echo -e "${BLUE}Testing connectivity...${NC}"
            if timeout 10 curl -s -I "http://$traefik_ip" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ New IP is accessible${NC}"
            else
                echo -e "${YELLOW}⚠ New IP connectivity test failed (may need network configuration)${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Traefik not yet assigned IP from new subnet${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Traefik IP not yet assigned${NC}"
    fi
    echo ""
}

# Function to show migration summary
show_migration_summary() {
    echo -e "${YELLOW}Migration Summary:${NC}"
    echo ""
    echo -e "${BLUE}Before:${NC}"
    echo -e "${YELLOW}• Single IP: 10.0.1.214${NC}"
    echo -e "${YELLOW}• No redundancy${NC}"
    echo -e "${YELLOW}• Network connectivity issues${NC}"
    echo ""
    echo -e "${BLUE}After:${NC}"
    echo -e "${GREEN}• Dedicated subnet: 10.0.2.8/29${NC}"
    echo -e "${GREEN}• 6 usable IPs (10.0.2.9-14)${NC}"
    echo -e "${GREEN}• Proper redundancy and failover${NC}"
    echo -e "${GREEN}• Clean separation from node IPs${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "${YELLOW}1. Update DNS records to point to new IPs${NC}"
    echo -e "${YELLOW}2. Test connectivity from external networks${NC}"
    echo -e "${YELLOW}3. Update firewall rules if needed${NC}"
    echo -e "${YELLOW}4. Monitor service assignments${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting MetalLB subnet migration...${NC}"
    echo ""
    
    # Show current configuration
    show_current_config
    
    # Create backup
    create_backup
    
    # Show subnet analysis
    echo -e "${YELLOW}Subnet Analysis:${NC}"
    echo -e "${BLUE}Network: $SUBNET${NC}"
    echo -e "${BLUE}Usable IPs: $FIRST_USABLE - $LAST_USABLE (6 total)${NC}"
    echo ""
    
    # Show configuration options
    create_single_pool_config
    create_service_specific_pools
    create_priority_config
    
    # Ask user which configuration to apply
    echo -e "${YELLOW}Which configuration would you like to apply?${NC}"
    echo "1. Single Pool (all 6 IPs in one pool)"
    echo "2. Service-Specific Pools (web/internal/backup)"
    echo "3. Priority-Based Pools (primary/secondary/reserve)"
    echo "4. Show configurations only (no changes)"
    echo ""
    echo -n "Enter choice (1-4): "
    read -r choice
    
    case $choice in
        1)
            apply_configuration "/tmp/metallb-single-pool-subnet.yaml" "Single Pool Configuration"
            test_new_ips
            ;;
        2)
            apply_configuration "/tmp/metallb-service-pools-subnet.yaml" "Service-Specific Pools"
            test_new_ips
            ;;
        3)
            apply_configuration "/tmp/metallb-priority-subnet.yaml" "Priority-Based Configuration"
            test_new_ips
            ;;
        4)
            echo -e "${GREEN}Configuration files created in /tmp/ for review${NC}"
            ls -la /tmp/metallb-*subnet*.yaml
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    # Show migration summary
    show_migration_summary
    
    echo ""
    echo -e "${GREEN}MetalLB subnet migration completed!${NC}"
}

# Run main function
main "$@"
