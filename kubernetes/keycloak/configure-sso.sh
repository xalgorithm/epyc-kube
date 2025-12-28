#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Keycloak SSO Configuration Script${NC}"
echo "This script will configure Keycloak as an SSO provider for Grafana, n8n, and WordPress."
echo

# Source Vault credentials
if [ -f ~/.vault/credentials ]; then
    source ~/.vault/credentials
    export VAULT_ADDR=${VAULT_ADDR:-"https://vault.admin.im"}
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo -e "${BLUE}Using Vault credentials from ~/.vault/credentials${NC}"
        vault login $VAULT_ROOT_TOKEN > /dev/null
    fi
fi

# Configuration variables
KEYCLOAK_URL="https://login.admin.im"
KEYCLOAK_REALM="admin-apps"
KEYCLOAK_ADMIN_USER="admin"
KEYCLOAK_ADMIN_PASSWORD="changeme123"

# Application URLs
GRAFANA_URL="https://grafana.admin.im"
N8N_URL="https://automate.admin.im"
WORDPRESS_URL="https://blog.admin.im"

# Client IDs and secrets
GRAFANA_CLIENT_ID="grafana"
GRAFANA_CLIENT_SECRET=$(openssl rand -hex 16)
N8N_CLIENT_ID="n8n"
N8N_CLIENT_SECRET=$(openssl rand -hex 16)
WORDPRESS_CLIENT_ID="wordpress"
WORDPRESS_CLIENT_SECRET=$(openssl rand -hex 16)

# Port forwarding setup (will be killed at exit)
setup_port_forwarding() {
    echo -e "${BLUE}Setting up port forwarding to Keycloak...${NC}"
    kubectl port-forward svc/keycloak -n keycloak 8080:80 > /dev/null 2>&1 &
    FORWARDING_PID=$!
    
    # Wait for port forwarding to establish
    sleep 5
    
    # Verify port forwarding is working
    for i in {1..5}; do
        if curl -s http://localhost:8080 > /dev/null; then
            echo -e "${GREEN}Port forwarding established successfully.${NC}"
            # Register cleanup function
            trap cleanup EXIT
            return 0
        fi
        echo -e "${YELLOW}Waiting for port forwarding to be established (attempt $i)...${NC}"
        sleep 2
    done
    
    echo -e "${RED}Failed to establish port forwarding. Exiting.${NC}"
    cleanup
    exit 1
}

cleanup() {
    if [ -n "$FORWARDING_PID" ]; then
        echo -e "${BLUE}Cleaning up port forwarding...${NC}"
        kill $FORWARDING_PID 2>/dev/null || true
    fi
}

# Get admin token
get_admin_token() {
    echo -e "${BLUE}Getting admin token from Keycloak...${NC}"
    for i in {1..3}; do
        ADMIN_TOKEN=$(curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=$KEYCLOAK_ADMIN_USER" \
            -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
            -d "grant_type=password" \
            -d "client_id=admin-cli" \
            "http://localhost:8080/realms/master/protocol/openid-connect/token" | jq -r .access_token)
        
        if [ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "null" ]; then
            echo -e "${GREEN}Successfully obtained admin token.${NC}"
            return 0
        fi
        echo -e "${YELLOW}Failed to get admin token. Retrying (attempt $i)...${NC}"
        sleep 3
    done
    
    echo -e "${RED}Failed to get admin token after multiple attempts. Please check your Keycloak credentials.${NC}"
    exit 1
}

# Create realm
create_realm() {
    echo -e "${BLUE}Creating realm $KEYCLOAK_REALM...${NC}"
    
    # Check if realm already exists
    REALM_EXISTS=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms" | jq -r '.[] | select(.realm=="'$KEYCLOAK_REALM'") | .realm')
    
    if [ "$REALM_EXISTS" == "$KEYCLOAK_REALM" ]; then
        echo -e "${YELLOW}Realm $KEYCLOAK_REALM already exists. Skipping creation.${NC}"
    else
        # Create realm
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
}

# Create client
create_client() {
    local client_id=$1
    local client_secret=$2
    local redirect_uris=$3
    local name=$4
    
    echo -e "${BLUE}Creating client $client_id...${NC}"
    
    # Check if client already exists
    CLIENT_EXISTS=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$client_id'") | .clientId')
    
    if [ "$CLIENT_EXISTS" == "$client_id" ]; then
        echo -e "${YELLOW}Client $client_id already exists. Updating...${NC}"
        
        # Get client ID
        CLIENT_UUID=$(curl -s -X GET \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$client_id'") | .id')
        
        # Update client
        curl -s -X PUT \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
                "clientId": "'$client_id'",
                "name": "'$name'",
                "enabled": true,
                "protocol": "openid-connect",
                "publicClient": false,
                "redirectUris": '$redirect_uris',
                "webOrigins": ["*"],
                "standardFlowEnabled": true,
                "implicitFlowEnabled": false,
                "directAccessGrantsEnabled": true,
                "serviceAccountsEnabled": false,
                "authorizationServicesEnabled": false,
                "fullScopeAllowed": true,
                "clientAuthenticatorType": "client-secret",
                "secret": "'$client_secret'"
            }' \
            "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"
    else
        # Create client
        HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
                "clientId": "'$client_id'",
                "name": "'$name'",
                "enabled": true,
                "protocol": "openid-connect",
                "publicClient": false,
                "redirectUris": '$redirect_uris',
                "webOrigins": ["*"],
                "standardFlowEnabled": true,
                "implicitFlowEnabled": false,
                "directAccessGrantsEnabled": true,
                "serviceAccountsEnabled": false,
                "authorizationServicesEnabled": false,
                "fullScopeAllowed": true,
                "clientAuthenticatorType": "client-secret",
                "secret": "'$client_secret'"
            }' \
            "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients")
        
        if [ "$HTTP_RESPONSE" == "201" ] || [ "$HTTP_RESPONSE" == "200" ]; then
            echo -e "${GREEN}Client $client_id created successfully.${NC}"
        else
            echo -e "${RED}Failed to create client $client_id. HTTP response: $HTTP_RESPONSE${NC}"
            exit 1
        fi
    fi
}

# Create test user
create_test_user() {
    echo -e "${BLUE}Creating test user...${NC}"
    
    # Check if user already exists
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
}

# Update Grafana configuration
update_grafana_config() {
    echo -e "${BLUE}Updating Grafana configuration...${NC}"
    
    # Check if grafana-config exists
    if ! kubectl get configmap -n monitoring grafana-config &>/dev/null; then
        echo -e "${YELLOW}Grafana config map not found. Creating new one...${NC}"
        
        # Create a basic Grafana config
        GRAFANA_INI_CONTENT=$(cat <<EOF
[auth]
disable_login_form = false

[auth.generic_oauth]
enabled = true
name = Keycloak
allow_sign_up = true
client_id = $GRAFANA_CLIENT_ID
client_secret = $GRAFANA_CLIENT_SECRET
scopes = openid email profile
auth_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth
token_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token
api_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo
role_attribute_path = contains(realm_access.roles[*], 'admin') && 'Admin' || contains(realm_access.roles[*], 'editor') && 'Editor' || 'Viewer'
EOF
)
        
        # Create the ConfigMap
        kubectl create configmap -n monitoring grafana-config --from-literal=grafana.ini="$GRAFANA_INI_CONTENT"
    else
        # Prepare updated Grafana configuration
        GRAFANA_INI_UPDATE=$(cat <<EOF
[auth]
disable_login_form = false

[auth.generic_oauth]
enabled = true
name = Keycloak
allow_sign_up = true
client_id = $GRAFANA_CLIENT_ID
client_secret = $GRAFANA_CLIENT_SECRET
scopes = openid email profile
auth_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth
token_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token
api_url = $KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo
role_attribute_path = contains(realm_access.roles[*], 'admin') && 'Admin' || contains(realm_access.roles[*], 'editor') && 'Editor' || 'Viewer'
EOF
)

        # Create a patch for the configmap
        echo '{
            "data": {
                "grafana.ini": "'"$(echo "$GRAFANA_INI_UPDATE" | sed 's/"/\\"/g')"'"
            }
        }' > /tmp/grafana-patch.json
        
        # Apply the patch
        kubectl patch configmap -n monitoring grafana-config --patch "$(cat /tmp/grafana-patch.json)" --type=merge
    fi
    
    # Find the Grafana deployment
    GRAFANA_DEPLOYMENT=$(kubectl get deployment -n monitoring -l app.kubernetes.io/name=grafana -o name | head -n 1)
    
    if [ -z "$GRAFANA_DEPLOYMENT" ]; then
        echo -e "${YELLOW}Grafana deployment not found. Looking for alternative labels...${NC}"
        GRAFANA_DEPLOYMENT=$(kubectl get deployment -n monitoring -l "app=grafana" -o name | head -n 1)
    fi
    
    if [ -z "$GRAFANA_DEPLOYMENT" ]; then
        echo -e "${RED}Grafana deployment not found. Skipping restart.${NC}"
    else
        # Restart Grafana
        echo -e "${BLUE}Restarting Grafana deployment: $GRAFANA_DEPLOYMENT${NC}"
        kubectl rollout restart $GRAFANA_DEPLOYMENT -n monitoring
        echo -e "${GREEN}Grafana restart initiated.${NC}"
    fi
    
    echo -e "${GREEN}Grafana configuration updated successfully.${NC}"
}

# Update n8n configuration
update_n8n_config() {
    echo -e "${BLUE}Updating n8n configuration...${NC}"
    
    # Check if n8n namespace exists
    if ! kubectl get namespace n8n &>/dev/null; then
        echo -e "${RED}n8n namespace does not exist. Skipping n8n configuration.${NC}"
        return
    fi
    
    # Create a secret for n8n SSO configuration
    kubectl create secret generic -n n8n n8n-sso-config \
        --from-literal=N8N_AUTH_OIDC_ENABLED=true \
        --from-literal=N8N_AUTH_OIDC_ISSUER_URL=$KEYCLOAK_URL/realms/$KEYCLOAK_REALM \
        --from-literal=N8N_AUTH_OIDC_CLIENT_ID=$N8N_CLIENT_ID \
        --from-literal=N8N_AUTH_OIDC_CLIENT_SECRET=$N8N_CLIENT_SECRET \
        --from-literal=N8N_AUTH_OIDC_SCOPES="openid profile email" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Check if n8n deployment exists
    if ! kubectl get deployment -n n8n n8n &>/dev/null; then
        echo -e "${RED}n8n deployment not found. Skipping deployment update.${NC}"
        return
    fi
    
    # Update n8n deployment to use the new secret
    echo -e "${BLUE}Updating n8n deployment to use SSO config...${NC}"
    kubectl patch deployment -n n8n n8n --type=json -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/envFrom/-",
            "value": {
                "secretRef": {
                    "name": "n8n-sso-config"
                }
            }
        }
    ]'
    
    # Restart n8n
    kubectl rollout restart deployment -n n8n n8n
    
    echo -e "${GREEN}n8n configuration updated successfully.${NC}"
}

# Update WordPress configuration
update_wordpress_config() {
    echo -e "${BLUE}Updating WordPress configuration...${NC}"
    
    # Check if wordpress namespace exists
    if ! kubectl get namespace wordpress &>/dev/null; then
        echo -e "${RED}WordPress namespace does not exist. Skipping WordPress configuration.${NC}"
        return
    fi
    
    # Create a secret for the WordPress OpenID Connect plugin
    kubectl create secret generic -n wordpress wordpress-sso-config \
        --from-literal=OPENID_CONNECT_CLIENT_ID=$WORDPRESS_CLIENT_ID \
        --from-literal=OPENID_CONNECT_CLIENT_SECRET=$WORDPRESS_CLIENT_SECRET \
        --from-literal=OPENID_CONNECT_ENDPOINT_LOGIN_URL=$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth \
        --from-literal=OPENID_CONNECT_ENDPOINT_TOKEN_URL=$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token \
        --from-literal=OPENID_CONNECT_ENDPOINT_USERINFO_URL=$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo \
        --from-literal=OPENID_CONNECT_ENDPOINT_LOGOUT_URL=$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/logout \
        --from-literal=OPENID_CONNECT_ENDPOINT_JWKS_URL=$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/certs \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Note: WordPress requires the OpenID Connect plugin to be installed
    echo -e "${YELLOW}Note: WordPress requires the 'OpenID Connect Generic' plugin to be installed.${NC}"
    echo -e "${YELLOW}Please install this plugin in WordPress and configure it with the values from the wordpress-sso-config secret.${NC}"
    
    echo -e "${GREEN}WordPress configuration created successfully.${NC}"
}

# Store client secrets in Vault
store_secrets_in_vault() {
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo -e "${BLUE}Storing client secrets in Vault...${NC}"
        
        # Store Grafana client secret
        vault kv put secret/grafana-sso \
            client_id="$GRAFANA_CLIENT_ID" \
            client_secret="$GRAFANA_CLIENT_SECRET" \
            auth_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/auth" \
            token_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token" \
            api_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/userinfo"
        
        # Store n8n client secret
        vault kv put secret/n8n-sso \
            client_id="$N8N_CLIENT_ID" \
            client_secret="$N8N_CLIENT_SECRET" \
            issuer_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM"
        
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
}

# Main execution flow
setup_port_forwarding
get_admin_token
create_realm

# Create clients
create_client "$GRAFANA_CLIENT_ID" "$GRAFANA_CLIENT_SECRET" \
    '["'$GRAFANA_URL'/login/generic_oauth", "'$GRAFANA_URL'/*"]' \
    "Grafana"

create_client "$N8N_CLIENT_ID" "$N8N_CLIENT_SECRET" \
    '["'$N8N_URL'/rest/oauth2-credential/callback", "'$N8N_URL'/", "'$N8N_URL'/*"]' \
    "n8n"

create_client "$WORDPRESS_CLIENT_ID" "$WORDPRESS_CLIENT_SECRET" \
    '["'$WORDPRESS_URL'/", "'$WORDPRESS_URL'/wp-login.php", "'$WORDPRESS_URL'/*"]' \
    "WordPress"

create_test_user

update_grafana_config
update_n8n_config
update_wordpress_config
store_secrets_in_vault

echo -e "${GREEN}Keycloak SSO configuration complete!${NC}"
echo -e "${YELLOW}Client Details:${NC}"
echo -e "Grafana: Client ID: $GRAFANA_CLIENT_ID, Client Secret: $GRAFANA_CLIENT_SECRET"
echo -e "n8n: Client ID: $N8N_CLIENT_ID, Client Secret: $N8N_CLIENT_SECRET"
echo -e "WordPress: Client ID: $WORDPRESS_CLIENT_ID, Client Secret: $WORDPRESS_CLIENT_SECRET"
echo
echo -e "${YELLOW}Test User:${NC}"
echo -e "Username: testuser"
echo -e "Password: testpassword"
echo -e "Email: testuser@example.com"
echo
echo -e "${YELLOW}Note:${NC} You may need to restart your applications for the changes to take effect."
echo -e "${YELLOW}Note:${NC} For WordPress, you need to install the 'OpenID Connect Generic' plugin." 