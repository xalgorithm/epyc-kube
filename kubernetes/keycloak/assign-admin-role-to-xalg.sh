#!/bin/bash

# Assign admin role to xalg user in Keycloak
# This script assigns the admin role to the xalg user for Grafana access

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
TARGET_USERNAME="xalg"

echo -e "${BLUE}Assigning admin role to user: $TARGET_USERNAME${NC}"

# Start port forwarding if not already running
if ! pgrep -f "kubectl port-forward.*keycloak" > /dev/null; then
    echo -e "${YELLOW}Starting port forward to Keycloak...${NC}"
    kubectl port-forward -n keycloak svc/keycloak 8080:80 &
    PORTFORWARD_PID=$!
    sleep 3
    CLEANUP_PORTFORWARD=true
else
    echo -e "${GREEN}Port forward to Keycloak already running.${NC}"
    CLEANUP_PORTFORWARD=false
fi

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

# Check if user exists
echo -e "${YELLOW}Checking if user $TARGET_USERNAME exists...${NC}"
USER_DATA=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users?username=$TARGET_USERNAME")

USER_ID=$(echo "$USER_DATA" | jq -r '.[0].id // empty')

if [ -z "$USER_ID" ]; then
    echo -e "${RED}User $TARGET_USERNAME not found in realm $KEYCLOAK_REALM.${NC}"
    echo -e "${YELLOW}Available users:${NC}"
    curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users" | jq -r '.[] | "  - " + .username'
    
    echo -e "${BLUE}Would you like me to create the user? (This script will exit for now)${NC}"
    exit 1
fi

echo -e "${GREEN}Found user $TARGET_USERNAME with ID: $USER_ID${NC}"

# Get current user roles
echo -e "${YELLOW}Checking current roles for user $TARGET_USERNAME...${NC}"
CURRENT_ROLES=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users/$USER_ID/role-mappings/realm")

echo -e "${BLUE}Current roles:${NC}"
echo "$CURRENT_ROLES" | jq -r '.[] | "  - " + .name'

# Check if admin role already assigned
if echo "$CURRENT_ROLES" | jq -e '.[] | select(.name=="admin")' > /dev/null; then
    echo -e "${GREEN}✓ User $TARGET_USERNAME already has admin role.${NC}"
else
    # Get admin role details
    echo -e "${YELLOW}Getting admin role details...${NC}"
    ADMIN_ROLE=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/roles/admin")
    
    if [ "$(echo "$ADMIN_ROLE" | jq -r '.name')" != "admin" ]; then
        echo -e "${RED}Admin role not found in realm.${NC}"
        exit 1
    fi
    
    # Assign admin role to user
    echo -e "${YELLOW}Assigning admin role to user $TARGET_USERNAME...${NC}"
    ASSIGN_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[$ADMIN_ROLE]" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users/$USER_ID/role-mappings/realm")
    
    if [ "$ASSIGN_RESPONSE" == "204" ]; then
        echo -e "${GREEN}✓ Admin role successfully assigned to user $TARGET_USERNAME.${NC}"
    else
        echo -e "${RED}✗ Failed to assign admin role (HTTP: $ASSIGN_RESPONSE).${NC}"
        exit 1
    fi
fi

# Verify role assignment
echo -e "${YELLOW}Verifying role assignment...${NC}"
UPDATED_ROLES=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users/$USER_ID/role-mappings/realm")

echo -e "${GREEN}Updated roles for user $TARGET_USERNAME:${NC}"
echo "$UPDATED_ROLES" | jq -r '.[] | "  ✓ " + .name'

# Cleanup port forward if we started it
if [ "$CLEANUP_PORTFORWARD" = true ]; then
    echo -e "${YELLOW}Cleaning up port forward...${NC}"
    kill $PORTFORWARD_PID 2>/dev/null || true
fi

echo -e "${GREEN}Role assignment completed!${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  - User: $TARGET_USERNAME"
echo "  - Realm: $KEYCLOAK_REALM"
echo "  - Role: admin (assigned)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Logout from Grafana if currently logged in"
echo "2. Login again via OAuth to get updated permissions"
echo "3. You should now have Grafana Admin access"




