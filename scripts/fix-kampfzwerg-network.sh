#!/bin/bash

# Fix Kampfzwerg Network Issues
# Attempts to fix MetalLB and network connectivity issues

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Kampfzwerg Network Fix${NC}"
echo -e "${BLUE}=====================${NC}"

# Function to restart MetalLB components
restart_metallb() {
    echo -e "${YELLOW}Restarting MetalLB components...${NC}"
    
    # Restart MetalLB controller
    kubectl rollout restart deployment/metallb-controller -n metallb-system
    
    # Restart MetalLB speakers
    kubectl rollout restart daemonset/metallb-speaker -n metallb-system
    
    echo -e "${BLUE}Waiting for MetalLB to be ready...${NC}"
    kubectl rollout status deployment/metallb-controller -n metallb-system --timeout=60s
    kubectl rollout status daemonset/metallb-speaker -n metallb-system --timeout=60s
    
    echo -e "${GREEN}✓ MetalLB components restarted${NC}"
}

# Function to update MetalLB IP pool to use a working IP
update_metallb_ip_pool() {
    echo -e "${YELLOW}Updating MetalLB IP pool...${NC}"
    
    # Use an IP that's in the same range as the nodes
    cat > /tmp/metallb-ip-pool-fix.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.1.215/32  # Try next IP in sequence
  autoAssign: true
  avoidBuggyIPs: false
EOF

    kubectl apply -f /tmp/metallb-ip-pool-fix.yaml
    
    echo -e "${GREEN}✓ MetalLB IP pool updated to use 10.0.1.215${NC}"
    rm -f /tmp/metallb-ip-pool-fix.yaml
}

# Function to restart Traefik service
restart_traefik() {
    echo -e "${YELLOW}Restarting Traefik to pick up new IP...${NC}"
    
    kubectl rollout restart deployment/traefik -n kube-system
    kubectl rollout status deployment/traefik -n kube-system --timeout=120s
    
    echo -e "${GREEN}✓ Traefik restarted${NC}"
}

# Function to check and fix DNS if needed
check_dns_update() {
    echo -e "${YELLOW}Checking if DNS needs updating...${NC}"
    
    # Get the new LoadBalancer IP
    NEW_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    echo -e "${BLUE}New Traefik LoadBalancer IP: $NEW_IP${NC}"
    
    # Check current DNS resolution
    CURRENT_DNS_IP=$(nslookup kampfzwerg.gray-beard.com | grep "Address:" | tail -1 | awk '{print $2}')
    
    if [ "$NEW_IP" != "$CURRENT_DNS_IP" ]; then
        echo -e "${YELLOW}⚠ DNS needs to be updated:${NC}"
        echo -e "${YELLOW}  Current DNS: $CURRENT_DNS_IP${NC}"
        echo -e "${YELLOW}  New IP: $NEW_IP${NC}"
        echo -e "${YELLOW}  Please update your DNS records to point kampfzwerg.gray-beard.com to $NEW_IP${NC}"
    else
        echo -e "${GREEN}✓ DNS is already pointing to the correct IP${NC}"
    fi
}

# Function to test connectivity after fixes
test_connectivity() {
    echo -e "${YELLOW}Testing connectivity after fixes...${NC}"
    
    # Get current LoadBalancer IP
    TRAEFIK_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    # Test direct IP connectivity
    echo -e "${BLUE}Testing direct IP connectivity to $TRAEFIK_IP...${NC}"
    if timeout 10 curl -s -I "http://$TRAEFIK_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Direct IP connectivity working${NC}"
    else
        echo -e "${RED}✗ Direct IP connectivity still failing${NC}"
        echo -e "${YELLOW}  This might be a network infrastructure issue${NC}"
    fi
    
    # Test domain connectivity
    echo -e "${BLUE}Testing domain connectivity...${NC}"
    if timeout 15 curl -s -I "https://kampfzwerg.gray-beard.com" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Domain connectivity working${NC}"
    else
        echo -e "${YELLOW}⚠ Domain connectivity still failing (DNS propagation may take time)${NC}"
    fi
}

# Function to provide alternative solutions
provide_alternatives() {
    echo -e "${YELLOW}Alternative Solutions:${NC}"
    
    echo -e "${BLUE}1. NodePort Access:${NC}"
    NODEPORT_HTTP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
    NODEPORT_HTTPS=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="websecure")].nodePort}')
    
    echo -e "${YELLOW}   You can access kampfzwerg via NodePort:${NC}"
    echo -e "${YELLOW}   HTTP:  http://10.0.1.211:$NODEPORT_HTTP (or any node IP)${NC}"
    echo -e "${YELLOW}   HTTPS: https://10.0.1.211:$NODEPORT_HTTPS (or any node IP)${NC}"
    
    echo -e "${BLUE}2. Port Forward (temporary):${NC}"
    echo -e "${YELLOW}   kubectl port-forward -n kampfzwerg svc/wordpress 8080:80${NC}"
    echo -e "${YELLOW}   Then access: http://localhost:8080${NC}"
    
    echo -e "${BLUE}3. Check Network Infrastructure:${NC}"
    echo -e "${YELLOW}   - Verify firewall rules allow traffic to 10.0.1.214-215${NC}"
    echo -e "${YELLOW}   - Check if the IP range is properly routed${NC}"
    echo -e "${YELLOW}   - Verify network switch/router configuration${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting kampfzwerg network fix...${NC}"
    echo ""
    
    # Show current status
    echo -e "${YELLOW}Current Status:${NC}"
    kubectl get svc traefik -n kube-system
    echo ""
    
    # Restart MetalLB
    restart_metallb
    echo ""
    
    # Update IP pool
    update_metallb_ip_pool
    echo ""
    
    # Restart Traefik
    restart_traefik
    echo ""
    
    # Wait a bit for things to settle
    echo -e "${BLUE}Waiting for services to stabilize...${NC}"
    sleep 30
    
    # Check DNS
    check_dns_update
    echo ""
    
    # Test connectivity
    test_connectivity
    echo ""
    
    # Provide alternatives
    provide_alternatives
    echo ""
    
    echo -e "${GREEN}Network fix attempt completed!${NC}"
    echo -e "${BLUE}New service status:${NC}"
    kubectl get svc traefik -n kube-system
}

# Run main function
main "$@"
