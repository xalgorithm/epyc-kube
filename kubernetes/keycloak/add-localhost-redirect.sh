#!/bin/bash

# Add localhost redirect URI to handle Grafana's internal redirect
# This fixes the redirect_uri mismatch issue

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

echo -e "${BLUE}Adding localhost redirect URI to fix OAuth flow...${NC}"

# Get admin token
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
CLIENT_UUID=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$GRAFANA_CLIENT_ID'") | .id')

# Get current client configuration
CURRENT_CONFIG=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID")

# Add localhost redirect URIs
echo -e "${YELLOW}Adding localhost redirect URIs...${NC}"
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq '
    .redirectUris = [
        "https://grafana.gray-beard.com/login/generic_oauth",
        "http://localhost:3000/login/generic_oauth",
        "http://127.0.0.1:3000/login/generic_oauth",
        "https://grafana.gray-beard.com/login/oauth",
        "https://grafana.gray-beard.com/oauth/callback",
        "https://grafana.gray-beard.com/api/auth/callback",
        "https://grafana.gray-beard.com/auth/callback",
        "https://grafana.gray-beard.com/*",
        "https://grafana.gray-beard.com/"
    ] |
    .webOrigins = ["https://grafana.gray-beard.com", "http://localhost:3000", "*"]
')

curl -s -X PUT \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_CONFIG" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"

# Verify the update
echo -e "${GREEN}✓ Updated redirect URIs:${NC}"
UPDATED_CLIENT=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID")

echo "$UPDATED_CLIENT" | jq -r '.redirectUris[]'

echo -e "${GREEN}Localhost redirect URIs added successfully!${NC}"

