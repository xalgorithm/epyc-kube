#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Configuring WordPress with Keycloak SSO${NC}"

# Configuration variables
KEYCLOAK_URL="https://login.gray-beard.com"
KEYCLOAK_REALM="xalg-apps"
WORDPRESS_URL="https://kampfzwerg.gray-beard.com"
WORDPRESS_CLIENT_ID="wordpress"
WORDPRESS_CLIENT_SECRET=$(openssl rand -hex 16)

# Step 1: Check if WordPress is running
echo -e "${BLUE}Checking if WordPress is running...${NC}"
if ! kubectl get deployment -n wordpress wordpress &>/dev/null; then
    echo -e "${RED}WordPress deployment not found. Exiting.${NC}"
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

# Step 6: Create client for WordPress
echo -e "${BLUE}Creating Keycloak client for WordPress...${NC}"
CLIENT_EXISTS=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$WORDPRESS_CLIENT_ID'") | .clientId')

if [ "$CLIENT_EXISTS" == "$WORDPRESS_CLIENT_ID" ]; then
    echo -e "${YELLOW}Client $WORDPRESS_CLIENT_ID already exists. Updating...${NC}"
    
    # Get client ID
    CLIENT_UUID=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$WORDPRESS_CLIENT_ID'") | .id')
    
    # Update client
    curl -s -X PUT \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "'$WORDPRESS_CLIENT_ID'",
            "name": "WordPress",
            "enabled": true,
            "protocol": "openid-connect",
            "publicClient": false,
            "redirectUris": ["'$WORDPRESS_URL'/", "'$WORDPRESS_URL'/wp-login.php", "'$WORDPRESS_URL'/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "clientAuthenticatorType": "client-secret",
            "secret": "'$WORDPRESS_CLIENT_SECRET'"
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"
else
    # Create client
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "'$WORDPRESS_CLIENT_ID'",
            "name": "WordPress",
            "enabled": true,
            "protocol": "openid-connect",
            "publicClient": false,
            "redirectUris": ["'$WORDPRESS_URL'/", "'$WORDPRESS_URL'/wp-login.php", "'$WORDPRESS_URL'/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "clientAuthenticatorType": "client-secret",
            "secret": "'$WORDPRESS_CLIENT_SECRET'"
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients")
    
    if [ "$HTTP_RESPONSE" == "201" ] || [ "$HTTP_RESPONSE" == "200" ]; then
        echo -e "${GREEN}Client $WORDPRESS_CLIENT_ID created successfully.${NC}"
    else
        echo -e "${RED}Failed to create client $WORDPRESS_CLIENT_ID. HTTP response: $HTTP_RESPONSE${NC}"
        exit 1
    fi
fi

# Step 7: Create WordPress SSO configuration
echo -e "${BLUE}Creating WordPress SSO configuration...${NC}"

# Create a secret for WordPress OpenID Connect plugin
echo -e "${BLUE}Creating/updating WordPress SSO config secret...${NC}"
kubectl create secret generic -n wordpress wordpress-sso-config \
    --from-literal=OPENID_CONNECT_CLIENT_ID="$WORDPRESS_CLIENT_ID" \
    --from-literal=OPENID_CONNECT_CLIENT_SECRET="$WORDPRESS_CLIENT_SECRET" \
    --from-literal=OPENID_CONNECT_ENDPOINT_LOGIN_URL="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth" \
    --from-literal=OPENID_CONNECT_ENDPOINT_TOKEN_URL="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token" \
    --from-literal=OPENID_CONNECT_ENDPOINT_USERINFO_URL="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo" \
    --from-literal=OPENID_CONNECT_ENDPOINT_LOGOUT_URL="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/logout" \
    --from-literal=OPENID_CONNECT_ENDPOINT_JWKS_URL="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/certs" \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}WordPress SSO config secret created/updated.${NC}"

# Create a ConfigMap with WordPress installation instructions
echo -e "${BLUE}Creating WordPress plugin installation instructions...${NC}"
INSTRUCTIONS=$(cat <<EOF
# WordPress OpenID Connect Plugin Installation and Configuration

To complete the WordPress SSO setup with Keycloak, follow these steps:

1. Log in to your WordPress admin dashboard (${WORDPRESS_URL}/wp-admin)
2. Go to "Plugins" > "Add New"
3. Search for "OpenID Connect Generic"
4. Install and activate the plugin
5. Go to "Settings" > "OpenID Connect Client"
6. Configure the plugin with the following settings:

Client ID: $WORDPRESS_CLIENT_ID
Client Secret: $WORDPRESS_CLIENT_SECRET
OpenID Scope: openid email profile
Login Endpoint URL: $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth
Userinfo Endpoint URL: $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo
Token Validation Endpoint URL: $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token
End Session Endpoint URL: $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/logout
Identity Key: preferred_username
Link Existing Users: Enabled

7. Click "Save Changes"

The values are also stored in the 'wordpress-sso-config' secret in the 'wordpress' namespace.
EOF
)

kubectl create configmap -n wordpress wordpress-sso-instructions \
    --from-literal=instructions.txt="$INSTRUCTIONS" \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}WordPress plugin installation instructions created.${NC}"

# Store client secrets in Vault if available
if command -v vault &>/dev/null && [ -f ~/.vault/credentials ]; then
    echo -e "${BLUE}Storing client secrets in Vault...${NC}"
    source ~/.vault/credentials
    export VAULT_ADDR=${VAULT_ADDR:-"https://vault.gray-beard.com"}
    
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo -e "${BLUE}Using Vault credentials from ~/.vault/credentials${NC}"
        vault login $VAULT_ROOT_TOKEN > /dev/null

        # Store WordPress client secret
        vault kv put secret/wordpress-sso \
            client_id="$WORDPRESS_CLIENT_ID" \
            client_secret="$WORDPRESS_CLIENT_SECRET" \
            auth_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth" \
            token_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token" \
            userinfo_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo" \
            logout_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/logout" \
            jwks_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/certs"
            
        echo -e "${GREEN}Client secrets stored in Vault successfully.${NC}"
    else
        echo -e "${YELLOW}Vault token not available. Skipping storing secrets in Vault.${NC}"
    fi
fi

echo -e "${GREEN}WordPress configuration with Keycloak SSO completed!${NC}"
echo -e "${YELLOW}WordPress Client Details:${NC}"
echo -e "Client ID: $WORDPRESS_CLIENT_ID"
echo -e "Client Secret: $WORDPRESS_CLIENT_SECRET"
echo
echo -e "${YELLOW}Important:${NC} You need to install the OpenID Connect Generic plugin in WordPress."
echo -e "See the 'wordpress-sso-instructions' ConfigMap for detailed installation steps."
echo -e "You can view the instructions with: kubectl get configmap -n wordpress wordpress-sso-instructions -o jsonpath='{.data.instructions\\.txt}'"
echo -e "Or use a tool like kubectl port-forward to access the WordPress admin dashboard and install the plugin." 
