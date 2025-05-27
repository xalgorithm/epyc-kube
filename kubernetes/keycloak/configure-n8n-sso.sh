#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Configuring n8n with Keycloak SSO${NC}"

# Configuration variables
KEYCLOAK_URL="https://login.gray-beard.com"
KEYCLOAK_REALM="xalg-apps"
N8N_URL="https://automate.gray-beard.com"
N8N_CLIENT_ID="n8n"
N8N_CLIENT_SECRET=$(openssl rand -hex 16)

# Step 1: Check if n8n is running
echo -e "${BLUE}Checking if n8n is running...${NC}"
if ! kubectl get deployment -n n8n n8n &>/dev/null; then
    echo -e "${RED}n8n deployment not found. Exiting.${NC}"
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

# Step 6: Create client for n8n
echo -e "${BLUE}Creating Keycloak client for n8n...${NC}"
CLIENT_EXISTS=$(curl -s -X GET \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$N8N_CLIENT_ID'") | .clientId')

if [ "$CLIENT_EXISTS" == "$N8N_CLIENT_ID" ]; then
    echo -e "${YELLOW}Client $N8N_CLIENT_ID already exists. Updating...${NC}"
    
    # Get client ID
    CLIENT_UUID=$(curl -s -X GET \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients" | jq -r '.[] | select(.clientId=="'$N8N_CLIENT_ID'") | .id')
    
    # Update client
    curl -s -X PUT \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "'$N8N_CLIENT_ID'",
            "name": "n8n",
            "enabled": true,
            "protocol": "openid-connect",
            "publicClient": false,
            "redirectUris": ["'$N8N_URL'/rest/oauth2-credential/callback", "'$N8N_URL'/", "'$N8N_URL'/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": true,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "clientAuthenticatorType": "client-secret",
            "secret": "'$N8N_CLIENT_SECRET'"
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients/$CLIENT_UUID"
else
    # Create client
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "'$N8N_CLIENT_ID'",
            "name": "n8n",
            "enabled": true,
            "protocol": "openid-connect",
            "publicClient": false,
            "redirectUris": ["'$N8N_URL'/rest/oauth2-credential/callback", "'$N8N_URL'/", "'$N8N_URL'/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": true,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "clientAuthenticatorType": "client-secret",
            "secret": "'$N8N_CLIENT_SECRET'"
        }' \
        "http://localhost:8080/admin/realms/$KEYCLOAK_REALM/clients")
    
    if [ "$HTTP_RESPONSE" == "201" ] || [ "$HTTP_RESPONSE" == "200" ]; then
        echo -e "${GREEN}Client $N8N_CLIENT_ID created successfully.${NC}"
    else
        echo -e "${RED}Failed to create client $N8N_CLIENT_ID. HTTP response: $HTTP_RESPONSE${NC}"
        exit 1
    fi
fi

# Step 7: Update n8n configuration
echo -e "${BLUE}Updating n8n configuration...${NC}"

# Create a secret for n8n SSO configuration
echo -e "${BLUE}Creating/updating n8n SSO config secret...${NC}"
kubectl create secret generic -n n8n n8n-sso-config \
    --from-literal=N8N_AUTH_OIDC_ENABLED=true \
    --from-literal=N8N_AUTH_OIDC_ISSUER_URL="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM" \
    --from-literal=N8N_AUTH_OIDC_CLIENT_ID="$N8N_CLIENT_ID" \
    --from-literal=N8N_AUTH_OIDC_CLIENT_SECRET="$N8N_CLIENT_SECRET" \
    --from-literal=N8N_AUTH_OIDC_SCOPES="openid profile email" \
    --from-literal=N8N_AUTH_OIDC_RESPONSE_TYPE="code" \
    --from-literal=N8N_AUTH_OIDC_CALLBACK_URL="$N8N_URL/rest/oauth2-credential/callback" \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}n8n SSO config secret created/updated.${NC}"

# Check if n8n deployment already has the secret mounted
echo -e "${BLUE}Checking if n8n deployment already has the SSO config mounted...${NC}"
SECRET_MOUNTED=$(kubectl get deployment -n n8n n8n -o json | jq -r '.spec.template.spec.containers[0].envFrom[] | select(.secretRef.name == "n8n-sso-config") | .secretRef.name' 2>/dev/null || echo "")

if [ -z "$SECRET_MOUNTED" ]; then
    echo -e "${BLUE}Updating n8n deployment to use SSO config...${NC}"
    # Update n8n deployment to use the new secret
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
else
    echo -e "${YELLOW}n8n deployment already has the SSO config mounted.${NC}"
fi

# Restart n8n
echo -e "${BLUE}Restarting n8n deployment...${NC}"
kubectl rollout restart deployment/n8n -n n8n
echo -e "${GREEN}n8n restart initiated.${NC}"

# Store client secrets in Vault if available
if command -v vault &>/dev/null && [ -f ~/.vault/credentials ]; then
    echo -e "${BLUE}Storing client secrets in Vault...${NC}"
    source ~/.vault/credentials
    export VAULT_ADDR=${VAULT_ADDR:-"https://vault.gray-beard.com"}
    
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo -e "${BLUE}Using Vault credentials from ~/.vault/credentials${NC}"
        vault login $VAULT_ROOT_TOKEN > /dev/null

        # Store n8n client secret
        vault kv put secret/n8n-sso \
            client_id="$N8N_CLIENT_ID" \
            client_secret="$N8N_CLIENT_SECRET" \
            issuer_url="$KEYCLOAK_URL/realms/$KEYCLOAK_REALM"
            
        echo -e "${GREEN}Client secrets stored in Vault successfully.${NC}"
    else
        echo -e "${YELLOW}Vault token not available. Skipping storing secrets in Vault.${NC}"
    fi
fi

echo -e "${GREEN}n8n configuration with Keycloak SSO completed!${NC}"
echo -e "${YELLOW}n8n Client Details:${NC}"
echo -e "Client ID: $N8N_CLIENT_ID"
echo -e "Client Secret: $N8N_CLIENT_SECRET"
echo -e "Issuer URL: $KEYCLOAK_URL/realms/$KEYCLOAK_REALM"
echo
echo -e "${YELLOW}Note:${NC} You may need to wait a moment for n8n to restart before the changes take effect." 