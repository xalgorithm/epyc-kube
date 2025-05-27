#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Configuring Grafana with Keycloak SSO${NC}"

# Configuration variables
KEYCLOAK_URL="https://login.gray-beard.com"
KEYCLOAK_REALM="xalg-apps"
GRAFANA_URL="https://grafana.gray-beard.com"
GRAFANA_CLIENT_ID="grafana"
GRAFANA_CLIENT_SECRET=$(openssl rand -hex 16)

# Step 1: Check if Grafana is running
echo -e "${BLUE}Checking if Grafana is running...${NC}"
if ! kubectl get deployment -n monitoring -l "app.kubernetes.io/name=grafana" &>/dev/null && \
   ! kubectl get deployment -n monitoring -l "app=grafana" &>/dev/null; then
    echo -e "${RED}Grafana deployment not found. Exiting.${NC}"
    exit 1
fi

# Step 2: Check if Keycloak is running
echo -e "${BLUE}Checking if Keycloak is running...${NC}"
if ! kubectl get deployment -n keycloak keycloak &>/dev/null; then
    echo -e "${RED}Keycloak deployment not found. Exiting.${NC}"
    exit 1
fi

# Step 3: Port-forward to Keycloak
echo -e "${BLUE}Setting up port forwarding to Keycloak...${NC}"
kubectl port-forward svc/keycloak -n keycloak 8080:80 > /dev/null 2>&1 &
FORWARDING_PID=$!

# Register cleanup function
cleanup() {
    if [ -n "$FORWARDING_PID" ]; then
        echo -e "${BLUE}Cleaning up port forwarding...${NC}"
        kill $FORWARDING_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait for port forwarding to establish
sleep 5
if ! curl -s http://localhost:8080 > /dev/null; then
    echo -e "${RED}Failed to establish port forwarding to Keycloak. Exiting.${NC}"
    cleanup
    exit 1
fi
echo -e "${GREEN}Port forwarding established successfully.${NC}"

# Step 4: Get admin token
echo -e "${BLUE}Getting admin token from Keycloak...${NC}"
ADMIN_TOKEN=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=xalg" \
    -d "password=changeme123" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    "http://localhost:8080/realms/master/protocol/openid-connect/token" | jq -r .access_token)

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo -e "${RED}Failed to get admin token. Please check your Keycloak credentials.${NC}"
    exit 1
fi
echo -e "${GREEN}Successfully obtained admin token.${NC}"

# Step 5: Check if realm exists, create if not
echo -e "${BLUE}Checking if realm '$KEYCLOAK_REALM' exists...${NC}"
REALM_EXISTS=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms" | jq -r '.[] | select(.realm=="'$KEYCLOAK_REALM'") | .realm')

if [ "$REALM_EXISTS" == "$KEYCLOAK_REALM" ]; then
    echo -e "${YELLOW}Realm $KEYCLOAK_REALM already exists.${NC}"
else
    echo -e "${BLUE}Creating realm $KEYCLOAK_REALM...${NC}"
    curl -s -X POST \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "realm": "'$KEYCLOAK_REALM'",
            "enabled": true,
            "displayName": "XALG Applications",
            "displayNameHtml": "<div class=\"kc-logo-text\"><span>XALG Applications</span></div>",
            "sslRequired": "external",
            "registrationAllowed": false,
            "loginWithEmailAllowed": true,
            "duplicateEmailsAllowed": false,
            "resetPasswordAllowed": true,
            "editUsernameAllowed": false,
            "bruteForceProtected": true
        }' \
        "http://localhost:8080/admin/realms"
    
    # Verify realm was created
    REALM_CREATED=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms" | jq -r '.[] | select(.realm=="'$KEYCLOAK_REALM'") | .realm')
    
    if [ "$REALM_CREATED" == "$KEYCLOAK_REALM" ]; then
        echo -e "${GREEN}Realm $KEYCLOAK_REALM created successfully.${NC}"
    else
        echo -e "${RED}Failed to create realm $KEYCLOAK_REALM.${NC}"
        exit 1
    fi
fi

# Step 6: Create client for Grafana
echo -e "${BLUE}Creating Keycloak client for Grafana...${NC}"
CLIENT_EXISTS=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$GRAFANA_CLIENT_ID'") | .clientId')

if [ "$CLIENT_EXISTS" == "$GRAFANA_CLIENT_ID" ]; then
    echo -e "${YELLOW}Client $GRAFANA_CLIENT_ID already exists. Updating...${NC}"
    
    # Get client ID
    CLIENT_UUID=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$GRAFANA_CLIENT_ID'") | .id')
    
    # Update client
    curl -s -X PUT \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "'$GRAFANA_CLIENT_ID'",
            "name": "Grafana",
            "enabled": true,
            "protocol": "openid-connect",
            "publicClient": false,
            "redirectUris": ["'$GRAFANA_URL'/login/generic_oauth", "'$GRAFANA_URL'/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "clientAuthenticatorType": "client-secret",
            "secret": "'$GRAFANA_CLIENT_SECRET'"
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"
else
    # Create client
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "'$GRAFANA_CLIENT_ID'",
            "name": "Grafana",
            "enabled": true,
            "protocol": "openid-connect",
            "publicClient": false,
            "redirectUris": ["'$GRAFANA_URL'/login/generic_oauth", "'$GRAFANA_URL'/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "clientAuthenticatorType": "client-secret",
            "secret": "'$GRAFANA_CLIENT_SECRET'"
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients")
    
    if [ "$HTTP_RESPONSE" == "201" ] || [ "$HTTP_RESPONSE" == "200" ]; then
        echo -e "${GREEN}Client $GRAFANA_CLIENT_ID created successfully.${NC}"
    else
        echo -e "${RED}Failed to create client $GRAFANA_CLIENT_ID. HTTP response: $HTTP_RESPONSE${NC}"
        exit 1
    fi
fi

# Step 7: Create test user
echo -e "${BLUE}Creating test user...${NC}"
USER_EXISTS=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users" | jq -r '.[] | select(.username=="testuser") | .username')

if [ "$USER_EXISTS" == "testuser" ]; then
    echo -e "${YELLOW}User testuser already exists. Skipping creation.${NC}"
else
    # Create user
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "username": "testuser",
            "email": "testuser@example.com",
            "firstName": "Test",
            "lastName": "User",
            "enabled": true,
            "emailVerified": true,
            "credentials": [
                {
                    "type": "password",
                    "value": "testpassword",
                    "temporary": false
                }
            ]
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/users")
    
    if [ "$HTTP_RESPONSE" == "201" ] || [ "$HTTP_RESPONSE" == "200" ]; then
        echo -e "${GREEN}User testuser created successfully.${NC}"
    else
        echo -e "${RED}Failed to create test user. HTTP response: $HTTP_RESPONSE${NC}"
        exit 1
    fi
fi

# Step 8: Update Grafana configuration
echo -e "${BLUE}Updating Grafana configuration...${NC}"

# Find Grafana ConfigMap
if ! kubectl get configmap -n monitoring grafana-config &>/dev/null; then
    echo -e "${YELLOW}Grafana config map not found. Creating new one...${NC}"
    
    # Create the Grafana config content
    GRAFANA_INI="[auth]\ndisable_login_form = false\n\n[auth.generic_oauth]\nenabled = true\nname = Keycloak\nallow_sign_up = true\nclient_id = $GRAFANA_CLIENT_ID\nclient_secret = $GRAFANA_CLIENT_SECRET\nscopes = openid email profile\nauth_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth\ntoken_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token\napi_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo\nrole_attribute_path = contains(realm_access.roles[*], 'admin') && 'Admin' || contains(realm_access.roles[*], 'editor') && 'Editor' || 'Viewer'"
    
    # Create the ConfigMap
    kubectl create configmap -n monitoring grafana-config --from-literal=grafana.ini="$GRAFANA_INI"
else
    # Get existing config
    echo -e "${BLUE}Getting existing Grafana config...${NC}"
    
    # Create the updated Grafana config content
    GRAFANA_INI="[auth]\ndisable_login_form = false\n\n[auth.generic_oauth]\nenabled = true\nname = Keycloak\nallow_sign_up = true\nclient_id = $GRAFANA_CLIENT_ID\nclient_secret = $GRAFANA_CLIENT_SECRET\nscopes = openid email profile\nauth_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth\ntoken_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token\napi_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo\nrole_attribute_path = contains(realm_access.roles[*], 'admin') && 'Admin' || contains(realm_access.roles[*], 'editor') && 'Editor' || 'Viewer'"
    
    # Update using kubectl create with --dry-run and apply
    kubectl create configmap -n monitoring grafana-config --from-literal=grafana.ini="$GRAFANA_INI" --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}Grafana configuration updated.${NC}"
fi

# Find the Grafana deployment
echo -e "${BLUE}Finding Grafana deployment...${NC}"
GRAFANA_DEPLOYMENTS=$(kubectl get deployment -n monitoring | grep -i grafana | awk '{print $1}')

if [ -z "$GRAFANA_DEPLOYMENTS" ]; then
    echo -e "${RED}No Grafana deployments found. Skipping restart.${NC}"
else
    # Restart each Grafana deployment
    echo -e "${BLUE}Restarting Grafana deployments...${NC}"
    for deployment in $GRAFANA_DEPLOYMENTS; do
        echo -e "${BLUE}Restarting deployment: $deployment${NC}"
        kubectl rollout restart deployment/$deployment -n monitoring
    done
    echo -e "${GREEN}Grafana restart initiated.${NC}"
fi

echo -e "${GREEN}Grafana configuration with Keycloak SSO completed!${NC}"
echo -e "${YELLOW}Grafana Client Details:${NC}"
echo -e "Client ID: $GRAFANA_CLIENT_ID"
echo -e "Client Secret: $GRAFANA_CLIENT_SECRET"
echo
echo -e "${YELLOW}Test User:${NC}"
echo -e "Username: testuser"
echo -e "Password: testpassword"
echo -e "Email: testuser@example.com"
echo
echo -e "${YELLOW}Note:${NC} You may need to wait a moment for Grafana to restart before the changes take effect." 