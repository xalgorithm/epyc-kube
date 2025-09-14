#!/bin/bash

# Deploy Grafana Keycloak OAuth Configuration
# This script applies the Keycloak OAuth configuration to Grafana

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Deploying Grafana Keycloak OAuth configuration...${NC}"

# Apply the updated ConfigMap with OAuth settings
echo -e "${YELLOW}Applying Grafana auth ConfigMap with Keycloak OAuth...${NC}"
kubectl apply -f grafana-auth-config.yaml

# Apply the configuration to the Grafana deployment
echo -e "${YELLOW}Updating Grafana deployment to use OAuth configuration...${NC}"
./apply-auth-config.sh

# Wait for rollout to complete
echo -e "${YELLOW}Waiting for Grafana deployment rollout to complete...${NC}"
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=300s

# Verify the configuration is loaded
echo -e "${YELLOW}Verifying OAuth configuration...${NC}"
echo "Waiting 30 seconds for Grafana to be ready..."
sleep 30

# Get the Grafana pod name
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

if [ -n "$POD_NAME" ]; then
    echo -e "${BLUE}Checking OAuth configuration in pod: $POD_NAME${NC}"
    
    # Check if the grafana.ini file is mounted correctly
    echo -e "${YELLOW}Checking if grafana.ini is mounted:${NC}"
    kubectl exec -n monitoring "$POD_NAME" -- ls -la /etc/grafana/grafana.ini || echo "grafana.ini file not found"
    
    # Check if OAuth configuration is present
    echo -e "${YELLOW}Checking OAuth configuration in grafana.ini:${NC}"
    kubectl exec -n monitoring "$POD_NAME" -- grep -A 15 "\[auth.generic_oauth\]" /etc/grafana/grafana.ini || echo "OAuth configuration not found in grafana.ini"
    
    # Get Grafana service information
    echo -e "${YELLOW}Grafana service information:${NC}"
    kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana
    
    echo -e "${GREEN}OAuth configuration deployment completed!${NC}"
    echo -e "${BLUE}OAuth Configuration Applied:${NC}"
    echo "  - Provider: Keycloak-OAuth"
    echo "  - Auth URL: https://login.gray-beard.com/realms/xalg-apps/protocol/openid-connect/auth"
    echo "  - Token URL: https://login.gray-beard.com/realms/xalg-apps/protocol/openid-connect/token"
    echo "  - User Info URL: https://login.gray-beard.com/realms/xalg-apps/protocol/openid-connect/userinfo"
    echo "  - Client ID: grafana"
    echo "  - Role Mapping: admin -> Admin, editor -> Editor, default -> Viewer"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Ensure the 'grafana' client is configured in Keycloak"
    echo "2. Add the Grafana redirect URI to Keycloak client settings"
    echo "3. Test OAuth login via the Grafana web interface"
else
    echo -e "${RED}Could not find Grafana pod. Please check the deployment status.${NC}"
    exit 1
fi

echo -e "${GREEN}Grafana Keycloak OAuth configuration completed!${NC}"
