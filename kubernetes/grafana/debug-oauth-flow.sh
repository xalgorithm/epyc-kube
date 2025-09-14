#!/bin/bash

# Debug OAuth Flow
# This script helps debug the exact OAuth flow and capture error details

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}OAuth Flow Debug Script${NC}"
echo -e "${BLUE}=====================${NC}"

# Step 1: Test Grafana login page
echo -e "${YELLOW}1. Testing Grafana login page...${NC}"
LOGIN_PAGE=$(curl -s https://grafana.gray-beard.com/login)
if echo "$LOGIN_PAGE" | grep -q "Keycloak-OAuth\|generic_oauth"; then
    echo -e "${GREEN}✓ OAuth login option found on login page${NC}"
else
    echo -e "${YELLOW}⚠ OAuth login option not visible on login page${NC}"
fi

# Step 2: Test OAuth initiation
echo -e "${YELLOW}2. Testing OAuth initiation...${NC}"
OAUTH_RESPONSE=$(curl -s -I https://grafana.gray-beard.com/login/generic_oauth)
LOCATION_HEADER=$(echo "$OAUTH_RESPONSE" | grep -i "location:" || echo "No location header")
echo -e "${BLUE}OAuth initiation response:${NC}"
echo "$OAUTH_RESPONSE" | head -5

if echo "$LOCATION_HEADER" | grep -q "login.gray-beard.com"; then
    echo -e "${GREEN}✓ Redirect to Keycloak detected${NC}"
    REDIRECT_URL=$(echo "$LOCATION_HEADER" | sed 's/location: //i' | tr -d '\r\n')
    echo -e "${BLUE}Redirect URL:${NC} $REDIRECT_URL"
    
    # Parse redirect URI from the URL
    if echo "$REDIRECT_URL" | grep -q "redirect_uri="; then
        PARSED_REDIRECT_URI=$(echo "$REDIRECT_URL" | sed 's/.*redirect_uri=\([^&]*\).*/\1/' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))")
        echo -e "${BLUE}Parsed redirect URI:${NC} $PARSED_REDIRECT_URI"
    fi
else
    echo -e "${RED}✗ No redirect to Keycloak detected${NC}"
fi

# Step 3: Check current Grafana pod logs for OAuth attempts
echo -e "${YELLOW}3. Checking recent Grafana logs for OAuth activity...${NC}"
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
echo -e "${BLUE}Grafana pod:${NC} $POD_NAME"

echo -e "${BLUE}Recent OAuth-related logs:${NC}"
kubectl logs -n monitoring $POD_NAME --tail=50 | grep -i "oauth\|auth\|keycloak\|redirect" || echo "No OAuth-related logs found"

# Step 4: Provide troubleshooting steps
echo -e "${BLUE}=====================${NC}"
echo -e "${YELLOW}Troubleshooting Steps:${NC}"
echo ""
echo -e "${BLUE}If you're still getting redirect_uri errors:${NC}"
echo "1. Try the OAuth flow manually:"
echo "   - Visit: https://grafana.gray-beard.com/login"
echo "   - Click 'Sign in with Keycloak-OAuth'"
echo "   - Note the exact error message"
echo ""
echo "2. Check browser developer tools:"
echo "   - Open Network tab"
echo "   - Attempt OAuth login"
echo "   - Look for failed requests"
echo ""
echo "3. Alternative OAuth URLs to try:"
echo "   - https://grafana.gray-beard.com/login/oauth"
echo "   - https://grafana.gray-beard.com/oauth/callback"
echo ""
echo "4. If the error persists, the issue might be:"
echo "   - Clock synchronization between Grafana and Keycloak"
echo "   - SSL/TLS certificate issues"
echo "   - Network connectivity issues"
echo ""
echo -e "${GREEN}Current redirect URIs configured in Keycloak:${NC}"
echo "  - https://grafana.gray-beard.com/login/generic_oauth"
echo "  - https://grafana.gray-beard.com/login/oauth"
echo "  - https://grafana.gray-beard.com/oauth/callback"
echo "  - https://grafana.gray-beard.com/api/auth/callback"
echo "  - https://grafana.gray-beard.com/auth/callback"
echo "  - https://grafana.gray-beard.com/*"
echo "  - https://grafana.gray-beard.com/"

