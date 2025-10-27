#!/bin/bash

# Comprehensive Website Diagnostic Script
# Diagnoses both kampfzwerg.gray-beard.com and ethos.gray-beard.com

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Comprehensive Website Diagnostic${NC}"
echo -e "${BLUE}================================${NC}"

# Function to check pod status
check_pods() {
    local namespace=$1
    local site_name=$2
    
    echo -e "${YELLOW}Checking $site_name pods:${NC}"
    kubectl get pods -n $namespace
    
    # Check if any pods are ready
    local ready_pods=$(kubectl get pods -n $namespace --no-headers | grep -c "Running.*[1-9]/[1-9]" || echo "0")
    if [ "$ready_pods" -gt 0 ]; then
        echo -e "${GREEN}✓ $ready_pods pod(s) ready in $namespace${NC}"
    else
        echo -e "${RED}✗ No ready pods in $namespace${NC}"
    fi
    echo ""
}

# Function to check ingress
check_ingress() {
    local namespace=$1
    local site_name=$2
    
    echo -e "${YELLOW}Checking $site_name ingress:${NC}"
    kubectl get ingress -n $namespace
    echo ""
}

# Function to test connectivity
test_connectivity() {
    local domain=$1
    local site_name=$2
    
    echo -e "${YELLOW}Testing $site_name connectivity:${NC}"
    
    # Test DNS resolution
    echo -e "${BLUE}DNS Resolution:${NC}"
    if nslookup $domain >/dev/null 2>&1; then
        local dns_ip=$(nslookup $domain | grep "Address:" | tail -1 | awk '{print $2}')
        echo -e "${GREEN}✓ $domain resolves to $dns_ip${NC}"
    else
        echo -e "${RED}✗ DNS resolution failed for $domain${NC}"
    fi
    
    # Test HTTPS connectivity
    echo -e "${BLUE}HTTPS Connectivity:${NC}"
    if timeout 15 curl -s -I "https://$domain" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ HTTPS connection successful${NC}"
    else
        echo -e "${RED}✗ HTTPS connection failed${NC}"
    fi
    
    # Test HTTP connectivity
    echo -e "${BLUE}HTTP Connectivity:${NC}"
    if timeout 10 curl -s -I "http://$domain" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ HTTP connection successful${NC}"
    else
        echo -e "${RED}✗ HTTP connection failed${NC}"
    fi
    echo ""
}

# Function to check Traefik
check_traefik() {
    echo -e "${YELLOW}Checking Traefik Load Balancer:${NC}"
    
    # Check Traefik pod
    kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
    
    # Check Traefik service
    kubectl get svc traefik -n kube-system
    
    # Test LoadBalancer IP
    local lb_ip=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo -e "${BLUE}Testing LoadBalancer IP $lb_ip:${NC}"
    if timeout 10 curl -s -I "http://$lb_ip" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ LoadBalancer IP accessible${NC}"
    else
        echo -e "${RED}✗ LoadBalancer IP not accessible${NC}"
    fi
    echo ""
}

# Function to test NodePort access
test_nodeport() {
    echo -e "${YELLOW}Testing NodePort Access:${NC}"
    
    local nodeport_http=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
    local nodeport_https=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="websecure")].nodePort}')
    
    echo -e "${BLUE}NodePort URLs:${NC}"
    echo -e "${YELLOW}HTTP:  http://10.0.1.211:$nodeport_http${NC}"
    echo -e "${YELLOW}HTTPS: https://10.0.1.211:$nodeport_https${NC}"
    
    # Test NodePort for kampfzwerg
    echo -e "${BLUE}Testing kampfzwerg via NodePort:${NC}"
    if timeout 10 curl -s -I -H "Host: kampfzwerg.gray-beard.com" "http://10.0.1.211:$nodeport_http" | grep -q "30[0-9]"; then
        echo -e "${GREEN}✓ kampfzwerg NodePort working${NC}"
    else
        echo -e "${RED}✗ kampfzwerg NodePort failed${NC}"
    fi
    
    # Test NodePort for ethos
    echo -e "${BLUE}Testing ethos via NodePort:${NC}"
    if timeout 10 curl -s -I -H "Host: ethos.gray-beard.com" "http://10.0.1.211:$nodeport_http" | grep -q "30[0-9]"; then
        echo -e "${GREEN}✓ ethos NodePort working${NC}"
    else
        echo -e "${RED}✗ ethos NodePort failed${NC}"
    fi
    echo ""
}

# Function to provide solutions
provide_solutions() {
    echo -e "${YELLOW}Available Solutions:${NC}"
    
    local nodeport_http=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
    local nodeport_https=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="websecure")].nodePort}')
    
    echo -e "${BLUE}1. NodePort Access (Immediate):${NC}"
    echo -e "${GREEN}   kampfzwerg: http://10.0.1.211:$nodeport_http${NC}"
    echo -e "${GREEN}   ethos:      http://10.0.1.211:$nodeport_http${NC}"
    echo -e "${YELLOW}   (Use Host header or access directly)${NC}"
    echo ""
    
    echo -e "${BLUE}2. Port Forward (Local):${NC}"
    echo -e "${YELLOW}   kubectl port-forward -n kampfzwerg svc/wordpress 8080:80${NC}"
    echo -e "${YELLOW}   kubectl port-forward -n ethosenv svc/wordpress 8081:80${NC}"
    echo ""
    
    echo -e "${BLUE}3. Check Network Infrastructure:${NC}"
    echo -e "${YELLOW}   - Verify LoadBalancer IP routing${NC}"
    echo -e "${YELLOW}   - Check firewall rules${NC}"
    echo -e "${YELLOW}   - Contact network administrator${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting comprehensive website diagnostics...${NC}"
    echo ""
    
    # Check cluster status
    echo -e "${YELLOW}Cluster Status:${NC}"
    kubectl get nodes
    echo ""
    
    # Check Traefik
    check_traefik
    
    # Check kampfzwerg
    echo -e "${BLUE}=== KAMPFZWERG.ME ===${NC}"
    check_pods "kampfzwerg" "Kampfzwerg"
    check_ingress "kampfzwerg" "Kampfzwerg"
    test_connectivity "kampfzwerg.gray-beard.com" "Kampfzwerg"
    
    # Check ethos
    echo -e "${BLUE}=== ETHOS.XALG.IM ===${NC}"
    check_pods "ethosenv" "Ethos"
    check_ingress "ethosenv" "Ethos"
    test_connectivity "ethos.gray-beard.com" "Ethos"
    
    # Test NodePort
    test_nodeport
    
    # Provide solutions
    provide_solutions
    
    echo -e "${GREEN}Diagnostic completed!${NC}"
}

# Run main function
main "$@"
