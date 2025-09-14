#!/bin/bash

# Test Grafana Keycloak OAuth Configuration
# This script verifies that the OAuth configuration is properly applied

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Testing Grafana Keycloak OAuth configuration...${NC}"

# Check if ConfigMap exists and contains OAuth config
echo -e "${YELLOW}Checking if OAuth ConfigMap exists...${NC}"
if kubectl get configmap grafana-auth-config -n monitoring >/dev/null 2>&1; then
    echo -e "${GREEN}✓ grafana-auth-config ConfigMap exists${NC}"
    
    # Check if OAuth configuration is present
    echo -e "${YELLOW}Checking OAuth configuration in ConfigMap...${NC}"
    if kubectl get configmap grafana-auth-config -n monitoring -o yaml | grep -q "auth.generic_oauth"; then
        echo -e "${GREEN}✓ OAuth configuration found in ConfigMap${NC}"
    else
        echo -e "${RED}✗ OAuth configuration not found in ConfigMap${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ grafana-auth-config ConfigMap not found${NC}"
    exit 1
fi

# Check if Grafana deployment is using the ConfigMap
echo -e "${YELLOW}Checking if Grafana deployment uses the auth ConfigMap...${NC}"
if kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o yaml | grep -q "grafana-auth-config"; then
    echo -e "${GREEN}✓ Grafana deployment is configured to use auth ConfigMap${NC}"
else
    echo -e "${YELLOW}⚠ Grafana deployment may not be using the auth ConfigMap${NC}"
    echo -e "${BLUE}Run ./apply-auth-config.sh to apply the configuration${NC}"
fi

# Check if Grafana pod is running
echo -e "${YELLOW}Checking Grafana pod status...${NC}"
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    POD_STATUS=$(kubectl get pod "$POD_NAME" -n monitoring -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓ Grafana pod ($POD_NAME) is running${NC}"
        
        # Check if grafana.ini contains OAuth config
        echo -e "${YELLOW}Verifying OAuth config is loaded in pod...${NC}"
        if kubectl exec -n monitoring "$POD_NAME" -- grep -q "auth.generic_oauth" /etc/grafana/grafana.ini 2>/dev/null; then
            echo -e "${GREEN}✓ OAuth configuration is loaded in Grafana${NC}"
            
            # Show OAuth configuration details
            echo -e "${BLUE}OAuth Configuration Details:${NC}"
            kubectl exec -n monitoring "$POD_NAME" -- grep -A 15 "\[auth.generic_oauth\]" /etc/grafana/grafana.ini || echo "Could not retrieve OAuth details"
        else
            echo -e "${RED}✗ OAuth configuration not found in running pod${NC}"
            echo -e "${YELLOW}The configuration may need to be applied or the pod may need to restart${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Grafana pod status: $POD_STATUS${NC}"
    fi
else
    echo -e "${RED}✗ No Grafana pod found${NC}"
    exit 1
fi

# Get Grafana service URL
echo -e "${YELLOW}Getting Grafana access information...${NC}"
GRAFANA_SVC=$(kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$GRAFANA_SVC" ]; then
    echo -e "${BLUE}Grafana Service: $GRAFANA_SVC${NC}"
    kubectl get svc "$GRAFANA_SVC" -n monitoring
fi

echo -e "${GREEN}OAuth configuration test completed!${NC}"
echo ""
echo -e "${YELLOW}Next steps to complete OAuth setup:${NC}"
echo "1. Ensure the 'grafana' client exists in Keycloak realm 'xalg-apps'"
echo "2. Configure the client with the following settings:"
echo "   - Client ID: grafana"
echo "   - Client Secret: d4b855e1c84409b500571db8f12dd829"
echo "   - Valid Redirect URIs: https://your-grafana-url/login/generic_oauth"
echo "   - Assign appropriate roles (admin, editor) to users"
echo "3. Test OAuth login via the Grafana web interface"

