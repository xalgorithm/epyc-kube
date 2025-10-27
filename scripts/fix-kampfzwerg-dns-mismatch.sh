#!/bin/bash

# Fix Kampfzwerg DNS Mismatch
# Fixes the mismatch between DNS (10.0.1.214) and LoadBalancer IP (10.0.1.215)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Kampfzwerg DNS Mismatch Fix${NC}"
echo -e "${BLUE}===========================${NC}"

# Check current status
echo -e "${YELLOW}Current Status:${NC}"
DNS_IP=$(nslookup kampfzwerg.gray-beard.com | grep "Address:" | tail -1 | awk '{print $2}')
LB_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo -e "${BLUE}DNS points to: $DNS_IP${NC}"
echo -e "${BLUE}LoadBalancer IP: $LB_IP${NC}"

if [ "$DNS_IP" != "$LB_IP" ]; then
    echo -e "${RED}✗ DNS mismatch detected!${NC}"
    
    echo -e "${YELLOW}Choose a fix option:${NC}"
    echo "1. Restore LoadBalancer to use DNS IP ($DNS_IP)"
    echo "2. Show instructions to update DNS to new IP ($LB_IP)"
    echo "3. Use NodePort workaround"
    echo ""
    echo -n "Enter choice (1-3): "
    read -r choice
    
    case $choice in
        1)
            echo -e "${YELLOW}Restoring LoadBalancer to use $DNS_IP...${NC}"
            
            # Update MetalLB IP pool back to original IP
            cat > /tmp/metallb-restore-ip.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $DNS_IP/32
  autoAssign: true
  avoidBuggyIPs: false
EOF
            
            kubectl apply -f /tmp/metallb-restore-ip.yaml
            
            # Restart Traefik to pick up the change
            kubectl rollout restart deployment/traefik -n kube-system
            kubectl rollout status deployment/traefik -n kube-system --timeout=120s
            
            echo -e "${GREEN}✓ LoadBalancer restored to $DNS_IP${NC}"
            rm -f /tmp/metallb-restore-ip.yaml
            
            # Test connectivity
            echo -e "${BLUE}Testing connectivity...${NC}"
            sleep 10
            if timeout 15 curl -s -I "http://$DNS_IP" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Direct IP connectivity working${NC}"
            else
                echo -e "${RED}✗ Direct IP connectivity still failing${NC}"
                echo -e "${YELLOW}The network infrastructure issue persists${NC}"
            fi
            ;;
            
        2)
            echo -e "${YELLOW}DNS Update Instructions:${NC}"
            echo ""
            echo -e "${BLUE}You need to update your DNS records:${NC}"
            echo -e "${YELLOW}Domain: kampfzwerg.gray-beard.com${NC}"
            echo -e "${YELLOW}Current A record: $DNS_IP${NC}"
            echo -e "${YELLOW}New A record: $LB_IP${NC}"
            echo ""
            echo -e "${BLUE}Steps:${NC}"
            echo "1. Log into your DNS provider (domain registrar)"
            echo "2. Find the A record for kampfzwerg.gray-beard.com"
            echo "3. Change the IP from $DNS_IP to $LB_IP"
            echo "4. Save changes (propagation may take 5-60 minutes)"
            ;;
            
        3)
            echo -e "${YELLOW}NodePort Workaround:${NC}"
            echo ""
            echo -e "${BLUE}Access kampfzwerg using these URLs:${NC}"
            NODEPORT_HTTP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
            NODEPORT_HTTPS=$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name=="websecure")].nodePort}')
            
            echo -e "${GREEN}HTTP:  http://10.0.1.211:$NODEPORT_HTTP${NC}"
            echo -e "${GREEN}HTTPS: https://10.0.1.211:$NODEPORT_HTTPS${NC}"
            echo ""
            echo -e "${YELLOW}Or use any node IP: 10.0.1.211, 10.0.1.212, or 10.0.1.213${NC}"
            
            # Test NodePort
            echo -e "${BLUE}Testing NodePort access...${NC}"
            if curl -s -I -H "Host: kampfzwerg.gray-beard.com" "http://10.0.1.211:$NODEPORT_HTTP" | grep -q "308"; then
                echo -e "${GREEN}✓ NodePort access working${NC}"
            else
                echo -e "${RED}✗ NodePort access failed${NC}"
            fi
            ;;
            
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
else
    echo -e "${GREEN}✓ DNS and LoadBalancer IP match${NC}"
    
    # Test connectivity
    echo -e "${BLUE}Testing connectivity...${NC}"
    if timeout 10 curl -s -I "https://kampfzwerg.gray-beard.com" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ kampfzwerg.gray-beard.com is accessible${NC}"
    else
        echo -e "${RED}✗ kampfzwerg.gray-beard.com is not accessible${NC}"
        echo -e "${YELLOW}This may be a network infrastructure issue${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Current service status:${NC}"
kubectl get svc traefik -n kube-system
echo ""
echo -e "${BLUE}WordPress pods status:${NC}"
kubectl get pods -n kampfzwerg -l app=wordpress
