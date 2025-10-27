#!/bin/bash

# Kampfzwerg Network Diagnostic Script
# Diagnoses network connectivity issues for kampfzwerg.gray-beard.com

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Kampfzwerg Network Diagnostic${NC}"
echo -e "${BLUE}=============================${NC}"

# Function to check WordPress service
check_wordpress_service() {
    echo -e "${YELLOW}Checking WordPress Service:${NC}"
    
    # Check pod status
    echo -e "${BLUE}WordPress Pods:${NC}"
    kubectl get pods -n kampfzwerg -l app=wordpress
    
    # Check service
    echo -e "${BLUE}WordPress Service:${NC}"
    kubectl get svc wordpress -n kampfzwerg
    
    # Test internal connectivity
    echo -e "${BLUE}Testing internal service connectivity:${NC}"
    if kubectl exec -n kampfzwerg deployment/wordpress -c nginx -- curl -s -I http://localhost:80 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Internal WordPress service responding${NC}"
    else
        echo -e "${RED}✗ Internal WordPress service not responding${NC}"
    fi
}

# Function to check ingress configuration
check_ingress() {
    echo -e "${YELLOW}Checking Ingress Configuration:${NC}"
    
    # Check ingress
    echo -e "${BLUE}Ingress Details:${NC}"
    kubectl describe ingress wordpress -n kampfzwerg
    
    # Check TLS certificate
    echo -e "${BLUE}TLS Certificate:${NC}"
    kubectl get certificate -n kampfzwerg 2>/dev/null || echo "No certificates found"
}

# Function to check Traefik
check_traefik() {
    echo -e "${YELLOW}Checking Traefik Load Balancer:${NC}"
    
    # Check Traefik pod
    echo -e "${BLUE}Traefik Pod Status:${NC}"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
    
    # Check Traefik service
    echo -e "${BLUE}Traefik Service:${NC}"
    kubectl get svc traefik -n kube-system
    
    # Check recent Traefik logs
    echo -e "${BLUE}Recent Traefik Logs (last 10 lines):${NC}"
    kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=10 | grep -v "airflow" || echo "No relevant logs"
}

# Function to check MetalLB
check_metallb() {
    echo -e "${YELLOW}Checking MetalLB Configuration:${NC}"
    
    # Check MetalLB pods
    echo -e "${BLUE}MetalLB Pods:${NC}"
    kubectl get pods -n metallb-system
    
    # Check IP pool
    echo -e "${BLUE}IP Address Pool:${NC}"
    kubectl get ipaddresspool -n metallb-system
    
    # Check L2 advertisement
    echo -e "${BLUE}L2 Advertisement:${NC}"
    kubectl get l2advertisement -n metallb-system
    
    # Check MetalLB speaker logs
    echo -e "${BLUE}MetalLB Speaker Logs (recent errors):${NC}"
    kubectl logs -n metallb-system -l component=speaker --tail=20 | grep -E "(ERROR|WARN|announceFailed)" || echo "No recent errors"
}

# Function to check network connectivity
check_network_connectivity() {
    echo -e "${YELLOW}Checking Network Connectivity:${NC}"
    
    # Check DNS resolution
    echo -e "${BLUE}DNS Resolution:${NC}"
    nslookup kampfzwerg.gray-beard.com || echo "DNS resolution failed"
    
    # Check node IPs
    echo -e "${BLUE}Node IP Addresses:${NC}"
    kubectl get nodes -o wide
    
    # Test direct IP connectivity
    echo -e "${BLUE}Testing direct IP connectivity:${NC}"
    TRAEFIK_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "Traefik LoadBalancer IP: $TRAEFIK_IP"
    
    if timeout 5 curl -s -I "http://$TRAEFIK_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Direct IP connectivity working${NC}"
    else
        echo -e "${RED}✗ Direct IP connectivity failed${NC}"
    fi
    
    # Test domain connectivity
    echo -e "${BLUE}Testing domain connectivity:${NC}"
    if timeout 10 curl -s -I "https://kampfzwerg.gray-beard.com" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Domain connectivity working${NC}"
    else
        echo -e "${RED}✗ Domain connectivity failed${NC}"
    fi
}

# Function to provide recommendations
provide_recommendations() {
    echo -e "${YELLOW}Diagnostic Summary and Recommendations:${NC}"
    
    # Check if WordPress is healthy
    WP_READY=$(kubectl get pods -n kampfzwerg -l app=wordpress -o jsonpath='{.items[0].status.containerStatuses[*].ready}' | grep -o true | wc -l)
    if [ "$WP_READY" -eq 2 ]; then
        echo -e "${GREEN}✓ WordPress pods are healthy${NC}"
    else
        echo -e "${RED}✗ WordPress pods have issues${NC}"
        echo -e "${YELLOW}  → Check pod logs: kubectl logs -n kampfzwerg deployment/wordpress${NC}"
    fi
    
    # Check if Traefik is healthy
    TRAEFIK_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].status.containerStatuses[0].ready}')
    if [ "$TRAEFIK_READY" = "true" ]; then
        echo -e "${GREEN}✓ Traefik is healthy${NC}"
    else
        echo -e "${RED}✗ Traefik has issues${NC}"
        echo -e "${YELLOW}  → Check Traefik logs: kubectl logs -n kube-system -l app.kubernetes.io/name=traefik${NC}"
    fi
    
    # Check MetalLB speaker logs for errors
    if kubectl logs -n metallb-system -l component=speaker --tail=50 | grep -q "announceFailed"; then
        echo -e "${RED}✗ MetalLB has IP announcement issues${NC}"
        echo -e "${YELLOW}  → Possible fixes:${NC}"
        echo -e "${YELLOW}    1. Update MetalLB IP pool to use available IPs${NC}"
        echo -e "${YELLOW}    2. Check node network interfaces${NC}"
        echo -e "${YELLOW}    3. Restart MetalLB speaker pods${NC}"
    else
        echo -e "${GREEN}✓ MetalLB appears healthy${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Starting kampfzwerg network diagnostics...${NC}"
    echo ""
    
    check_wordpress_service
    echo ""
    
    check_ingress
    echo ""
    
    check_traefik
    echo ""
    
    check_metallb
    echo ""
    
    check_network_connectivity
    echo ""
    
    provide_recommendations
    echo ""
    
    echo -e "${GREEN}Diagnostic completed!${NC}"
}

# Run main function
main "$@"
