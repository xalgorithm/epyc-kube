#!/bin/bash

# Comprehensive Redirect URI Fix for Grafana
# This script adds multiple redirect URI variations to handle different OAuth flows

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

echo -e "${BLUE}Comprehensive Redirect URI Fix for Grafana...${NC}"

# Get admin token
echo -e "${YELLOW}Getting admin token...${NC}"
ADMIN_TOKEN=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$KEYCLOAK_ADMIN_USER&password=$KEYCLOAK_ADMIN_PASSWORD&grant_type=password&client_id=admin-cli" \
    "http://localhost:8080/realms/master/protocol/openid-connect/token" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo -e "${RED}Failed to get admin token.${NC}"
    exit 1
fi
echo -e "${GREEN}Successfully obtained admin token.${NC}"

# Get client UUID
echo -e "${YELLOW}Getting Grafana client UUID...${NC}"
CLIENT_UUID=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$GRAFANA_CLIENT_ID'") | .id')

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
    echo -e "${RED}Grafana client not found.${NC}"
    exit 1
fi
echo -e "${GREEN}Found client UUID: $CLIENT_UUID${NC}"

# Get current client configuration
CURRENT_CONFIG=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID")

# Update with comprehensive redirect URIs
echo -e "${YELLOW}Updating client with comprehensive redirect URIs...${NC}"
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg grafana_url "$GRAFANA_URL" '
    .redirectUris = [
        ($grafana_url + "/login/generic_oauth"),
        ($grafana_url + "/login/oauth"),
        ($grafana_url + "/oauth/callback"),
        ($grafana_url + "/api/auth/callback"),
        ($grafana_url + "/auth/callback"),
        ($grafana_url + "/*"),
        ($grafana_url + "/")
    ] |
    .webOrigins = [$grafana_url, "*"] |
    .rootUrl = $grafana_url |
    .baseUrl = "/" |
    .adminUrl = $grafana_url
')

curl -s -X PUT \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_CONFIG" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"

# Verify the update
echo -e "${YELLOW}Verifying comprehensive redirect URIs...${NC}"
UPDATED_CLIENT=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID")

echo -e "${GREEN}✓ Updated redirect URIs:${NC}"
echo "$UPDATED_CLIENT" | jq -r '.redirectUris[]'

echo -e "${GREEN}✓ Updated web origins:${NC}"
echo "$UPDATED_CLIENT" | jq -r '.webOrigins[]'

echo -e "${GREEN}Comprehensive redirect URI fix completed!${NC}"
echo -e "${BLUE}All possible Grafana OAuth callback URLs are now configured.${NC}"

