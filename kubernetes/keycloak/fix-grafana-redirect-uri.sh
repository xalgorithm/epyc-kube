#!/bin/bash

# Fix Grafana Keycloak Client Redirect URI
# This script updates the Grafana client in Keycloak with the correct redirect URI

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_ADMIN_USER="xalg"
KEYCLOAK_ADMIN_PASSWORD="changeme123"
KEYCLOAK_REALM="xalg-apps"
GRAFANA_CLIENT_ID="grafana"
GRAFANA_URL="https://grafana.gray-beard.com"
REDIRECT_URI="${GRAFANA_URL}/login/generic_oauth"

echo -e "${BLUE}Fixing Grafana Keycloak client redirect URI...${NC}"

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

# Get client ID (internal UUID)
echo -e "${YELLOW}Getting Grafana client UUID...${NC}"
CLIENT_UUID=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$GRAFANA_CLIENT_ID'") | .id')

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
    echo -e "${RED}Grafana client not found. Please run ./configure-grafana-sso.sh first.${NC}"
    exit 1
fi
echo -e "${GREEN}Found Grafana client UUID: $CLIENT_UUID${NC}"

# Get current client configuration
echo -e "${YELLOW}Getting current client configuration...${NC}"
CURRENT_CONFIG=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID")

echo -e "${BLUE}Current redirect URIs:${NC}"
echo "$CURRENT_CONFIG" | jq -r '.redirectUris[]?' || echo "No redirect URIs configured"

# Update client with correct redirect URI
echo -e "${YELLOW}Updating client with correct redirect URI...${NC}"
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg redirect_uri "$REDIRECT_URI" --arg grafana_url "$GRAFANA_URL" '
    .redirectUris = [$redirect_uri] |
    .webOrigins = [$grafana_url] |
    .rootUrl = $grafana_url |
    .baseUrl = "/login/generic_oauth"
')

curl -s -X PUT \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_CONFIG" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"

# Verify the update
echo -e "${YELLOW}Verifying the update...${NC}"
UPDATED_CLIENT=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID")

echo -e "${GREEN}✓ Updated redirect URIs:${NC}"
echo "$UPDATED_CLIENT" | jq -r '.redirectUris[]?'

echo -e "${GREEN}✓ Updated web origins:${NC}"
echo "$UPDATED_CLIENT" | jq -r '.webOrigins[]?'

echo -e "${GREEN}Grafana Keycloak client redirect URI fixed!${NC}"
echo -e "${BLUE}Configuration details:${NC}"
echo "  - Redirect URI: $REDIRECT_URI"
echo "  - Web Origin: $GRAFANA_URL"
echo "  - Root URL: $GRAFANA_URL"
echo ""
echo -e "${YELLOW}You can now test OAuth login at: ${GRAFANA_URL}${NC}"
