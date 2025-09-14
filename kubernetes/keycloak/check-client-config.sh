#!/bin/bash

# Check Keycloak Client Configuration
# This script checks the actual redirect URIs configured in Keycloak

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_ADMIN_USER="xalg"
KEYCLOAK_ADMIN_PASSWORD="<REDACTED_PASSWORD>"
KEYCLOAK_REALM="xalg-apps"
GRAFANA_CLIENT_ID="grafana"

echo -e "${BLUE}Checking Keycloak Client Configuration...${NC}"

# Get admin token
echo -e "${YELLOW}Getting admin token...${NC}"
ADMIN_TOKEN=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$KEYCLOAK_ADMIN_USER&password=$KEYCLOAK_ADMIN_PASSWORD&grant_type=password&client_id=admin-cli" \
    "http://localhost:8080/realms/master/protocol/openid-connect/token" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo -e "${RED}Failed to get admin token. Please check your Keycloak credentials.${NC}"
    exit 1
fi
echo -e "${GREEN}Successfully obtained admin token.${NC}"

# Get client configuration
echo -e "${YELLOW}Getting Grafana client configuration...${NC}"
CLIENT_CONFIG=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq '.[] | select(.clientId=="'$GRAFANA_CLIENT_ID'")')

if [ -z "$CLIENT_CONFIG" ] || [ "$CLIENT_CONFIG" == "null" ]; then
    echo -e "${RED}Grafana client not found in realm $KEYCLOAK_REALM${NC}"
    exit 1
fi

echo -e "${GREEN}Found Grafana client configuration:${NC}"
echo -e "${BLUE}Client ID:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.clientId')"
echo -e "${BLUE}Client Name:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.name // "N/A"')"
echo -e "${BLUE}Enabled:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.enabled')"
echo -e "${BLUE}Protocol:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.protocol')"
echo -e "${BLUE}Public Client:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.publicClient')"

echo -e "${BLUE}Redirect URIs:${NC}"
REDIRECT_URIS=$(echo "$CLIENT_CONFIG" | jq -r '.redirectUris[]?' 2>/dev/null || echo "None configured")
if [ "$REDIRECT_URIS" == "None configured" ]; then
    echo -e "${RED}  ✗ No redirect URIs configured!${NC}"
else
    echo "$REDIRECT_URIS" | while read -r uri; do
        echo -e "${GREEN}  ✓ $uri${NC}"
    done
fi

echo -e "${BLUE}Web Origins:${NC}"
WEB_ORIGINS=$(echo "$CLIENT_CONFIG" | jq -r '.webOrigins[]?' 2>/dev/null || echo "None configured")
if [ "$WEB_ORIGINS" == "None configured" ]; then
    echo -e "${RED}  ✗ No web origins configured!${NC}"
else
    echo "$WEB_ORIGINS" | while read -r origin; do
        echo -e "${GREEN}  ✓ $origin${NC}"
    done
fi

echo -e "${BLUE}Root URL:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.rootUrl // "Not set"')"
echo -e "${BLUE}Base URL:${NC} $(echo "$CLIENT_CONFIG" | jq -r '.baseUrl // "Not set"')"

echo -e "${YELLOW}Expected redirect URI should be:${NC} https://grafana.gray-beard.com/login/generic_oauth"

