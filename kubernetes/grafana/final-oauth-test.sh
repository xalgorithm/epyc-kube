#!/bin/bash

# Final OAuth Test - Complete Integration Verification
# This script verifies the complete Grafana-Keycloak OAuth setup with roles

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Final OAuth Integration Test${NC}"
echo -e "${BLUE}===========================${NC}"

# Test 1: Verify Grafana OAuth configuration
echo -e "${YELLOW}1. Verifying Grafana OAuth configuration...${NC}"
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n monitoring $POD_NAME -- grep -q "allow_sign_up = true" /etc/grafana/grafana.ini; then
    echo -e "${GREEN}✓ OAuth sign-up is enabled${NC}"
else
    echo -e "${RED}✗ OAuth sign-up is not enabled${NC}"
fi

if kubectl exec -n monitoring $POD_NAME -- grep -q "root_url = https://grafana.gray-beard.com" /etc/grafana/grafana.ini; then
    echo -e "${GREEN}✓ Correct root URL configured${NC}"
else
    echo -e "${RED}✗ Root URL not configured correctly${NC}"
fi

# Test 2: Test OAuth flow
echo -e "${YELLOW}2. Testing OAuth redirect flow...${NC}"
OAUTH_RESPONSE=$(curl -s -I https://grafana.gray-beard.com/login/generic_oauth)
if echo "$OAUTH_RESPONSE" | grep -q "login.gray-beard.com"; then
    echo -e "${GREEN}✓ OAuth redirect to Keycloak working${NC}"
    REDIRECT_URI=$(echo "$OAUTH_RESPONSE" | grep -i location | sed 's/.*redirect_uri=\([^&]*\).*/\1/' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))")
    echo -e "${BLUE}Redirect URI: $REDIRECT_URI${NC}"
    
    if [ "$REDIRECT_URI" == "https://grafana.gray-beard.com/login/generic_oauth" ]; then
        echo -e "${GREEN}✓ Correct redirect URI format${NC}"
    else
        echo -e "${YELLOW}⚠ Redirect URI: $REDIRECT_URI${NC}"
    fi
else
    echo -e "${RED}✗ OAuth redirect not working${NC}"
fi

# Test 3: Check Keycloak roles (if port-forward is available)
echo -e "${YELLOW}3. Checking Keycloak realm roles...${NC}"
if curl -s http://localhost:8080/realms/master/.well-known/openid_configuration > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Keycloak accessible via port-forward${NC}"
    
    # Get admin token and check roles
    ADMIN_TOKEN=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=xalg&password=changeme123&grant_type=password&client_id=admin-cli" \
        "http://localhost:8080/realms/master/protocol/openid-connect/token" | jq -r '.access_token' 2>/dev/null || echo "null")
    
    if [ "$ADMIN_TOKEN" != "null" ] && [ -n "$ADMIN_TOKEN" ]; then
        ROLES=$(curl -s -X GET \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            "http://localhost:8080/admin/realms/xalg-apps/roles" 2>/dev/null || echo "[]")
        
        if echo "$ROLES" | jq -e '.[] | select(.name=="admin")' > /dev/null 2>&1; then
            echo -e "${GREEN}✓ admin role exists${NC}"
        else
            echo -e "${RED}✗ admin role missing${NC}"
        fi
        
        if echo "$ROLES" | jq -e '.[] | select(.name=="editor")' > /dev/null 2>&1; then
            echo -e "${GREEN}✓ editor role exists${NC}"
        else
            echo -e "${RED}✗ editor role missing${NC}"
        fi
        
        if echo "$ROLES" | jq -e '.[] | select(.name=="viewer")' > /dev/null 2>&1; then
            echo -e "${GREEN}✓ viewer role exists${NC}"
        else
            echo -e "${RED}✗ viewer role missing${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Could not verify roles (admin token failed)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Keycloak not accessible via port-forward - start with: kubectl port-forward -n keycloak svc/keycloak 8080:80${NC}"
fi

echo -e "${BLUE}===========================${NC}"
echo -e "${GREEN}OAuth Integration Test Complete!${NC}"
echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo "  - Grafana URL: https://grafana.gray-beard.com"
echo "  - OAuth Provider: Keycloak (xalg-apps realm)"
echo "  - Sign-up: Enabled"
echo "  - Role Mapping: admin → Admin, editor → Editor, default → Viewer"
echo ""
echo -e "${BLUE}Test Credentials:${NC}"
echo "  - Username: testuser"
echo "  - Password: testpassword"
echo "  - Assigned Role: admin (will get Grafana Admin access)"
echo ""
echo -e "${YELLOW}To test OAuth login:${NC}"
echo "1. Visit: https://grafana.gray-beard.com/login"
echo "2. Click 'Sign in with Keycloak-OAuth'"
echo "3. Login with testuser/testpassword"
echo "4. You should be redirected back to Grafana with Admin privileges"
echo ""
echo -e "${BLUE}Role Assignment in Keycloak:${NC}"
echo "- Users with 'admin' role → Grafana Admin"
echo "- Users with 'editor' role → Grafana Editor"
echo "- All other users → Grafana Viewer"




