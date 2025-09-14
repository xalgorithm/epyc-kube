#!/bin/bash

# Final OAuth Test - Verify Grafana Keycloak Integration
# This script performs final verification of the OAuth setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Final OAuth Integration Test${NC}"
echo -e "${BLUE}=============================${NC}"

# Test 1: Check Grafana is accessible
echo -e "${YELLOW}1. Testing Grafana accessibility...${NC}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://grafana.gray-beard.com)
if [ "$HTTP_STATUS" == "200" ]; then
    echo -e "${GREEN}✓ Grafana is accessible (HTTP $HTTP_STATUS)${NC}"
else
    echo -e "${RED}✗ Grafana not accessible (HTTP $HTTP_STATUS)${NC}"
fi

# Test 2: Check OAuth configuration in pod
echo -e "${YELLOW}2. Verifying OAuth configuration in Grafana pod...${NC}"
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n monitoring $POD_NAME -- grep -q "client_secret = 8e66e24ad167d20622a3dc8ad2c8c8b1" /etc/grafana/grafana.ini; then
    echo -e "${GREEN}✓ OAuth configuration is correctly loaded${NC}"
else
    echo -e "${RED}✗ OAuth configuration not found or incorrect${NC}"
fi

# Test 3: Check Keycloak endpoints
echo -e "${YELLOW}3. Testing Keycloak OAuth endpoints...${NC}"
AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://login.gray-beard.com/realms/xalg-apps/protocol/openid-connect/auth)
if [ "$AUTH_STATUS" == "400" ]; then
    echo -e "${GREEN}✓ Keycloak auth endpoint is accessible (HTTP $AUTH_STATUS - expected for GET without params)${NC}"
else
    echo -e "${RED}✗ Keycloak auth endpoint issue (HTTP $AUTH_STATUS)${NC}"
fi

# Test 4: Check if OAuth login is available
echo -e "${YELLOW}4. Testing OAuth login availability...${NC}"
if curl -s https://grafana.gray-beard.com/login | grep -q "Keycloak-OAuth\|generic_oauth"; then
    echo -e "${GREEN}✓ OAuth login option is available on Grafana login page${NC}"
else
    echo -e "${YELLOW}⚠ OAuth login option may not be visible (basic auth might be disabled)${NC}"
fi

echo -e "${BLUE}=============================${NC}"
echo -e "${GREEN}OAuth Integration Test Complete!${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  - Grafana URL: https://grafana.gray-beard.com"
echo "  - OAuth Provider: Keycloak-OAuth"
echo "  - Keycloak Realm: xalg-apps"
echo "  - Client ID: grafana"
echo "  - Redirect URI: https://grafana.gray-beard.com/login/generic_oauth"
echo ""
echo -e "${BLUE}Test Credentials:${NC}"
echo "  - Username: testuser"
echo "  - Password: testpassword"
echo "  - Email: testuser@example.com"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Visit https://grafana.gray-beard.com"
echo "2. Look for 'Sign in with Keycloak-OAuth' button"
echo "3. Click it to test OAuth login"
echo "4. Use the test credentials above"

