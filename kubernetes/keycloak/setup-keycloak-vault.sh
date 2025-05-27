#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Keycloak Vault Credentials Setup${NC}"
echo "This script will set up Keycloak credentials in Vault."
echo

# Generate a secure random password if not provided
DEFAULT_ADMIN_PASSWORD=$(openssl rand -base64 12)
DEFAULT_DB_PASSWORD=$(openssl rand -base64 12)

# Get user input for credentials
read -p "Enter admin username (default: admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-"admin"}

read -s -p "Enter admin password (default: auto-generated): " ADMIN_PASSWORD
echo
ADMIN_PASSWORD=${ADMIN_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}

read -p "Enter database username (default: keycloak): " DB_USER
DB_USER=${DB_USER:-"keycloak"}

read -s -p "Enter database password (default: auto-generated): " DB_PASSWORD
echo
DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}

# Check if we can access Vault
if [ -f ~/.vault/credentials ] && command -v vault &> /dev/null; then
    echo -e "${BLUE}Setting up Keycloak credentials in Vault...${NC}"
    
    # Source Vault credentials
    source ~/.vault/credentials
    
    # Set Vault address
    export VAULT_ADDR=${VAULT_ADDR:-"https://vault.gray-beard.com"}
    
    # Try to log in with root token
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo -e "${BLUE}Logging into Vault...${NC}"
        if vault login "$VAULT_ROOT_TOKEN" &> /dev/null; then
            # Store Keycloak credentials in Vault
            echo -e "${BLUE}Storing Keycloak credentials in Vault...${NC}"
            vault kv put secret/keycloak \
                admin_user="$ADMIN_USER" \
                admin_password="$ADMIN_PASSWORD" \
                db_user="$DB_USER" \
                db_password="$DB_PASSWORD" \
                db_name="keycloak" \
                db_vendor="postgres"
            
            echo -e "${GREEN}Successfully stored Keycloak credentials in Vault!${NC}"
            
            # Create base64 encoded values for Kubernetes secret
            ADMIN_USER_B64=$(echo -n "$ADMIN_USER" | base64)
            ADMIN_PASSWORD_B64=$(echo -n "$ADMIN_PASSWORD" | base64)
            DB_USER_B64=$(echo -n "$DB_USER" | base64)
            DB_PASSWORD_B64=$(echo -n "$DB_PASSWORD" | base64)
            
            # Create a Kubernetes secret file
            cat > kubernetes/keycloak/keycloak-secret.yaml <<EOL
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-secret
  namespace: keycloak
type: Opaque
data:
  KEYCLOAK_ADMIN: ${ADMIN_USER_B64}
  KEYCLOAK_ADMIN_PASSWORD: ${ADMIN_PASSWORD_B64}
  KC_DB_USERNAME: ${DB_USER_B64}
  KC_DB_PASSWORD: ${DB_PASSWORD_B64}
EOL
            
            echo -e "${GREEN}Created Kubernetes secret file: kubernetes/keycloak/keycloak-secret.yaml${NC}"
        else
            echo -e "${RED}Could not log in to Vault with stored token. Credentials not stored.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}No Vault root token found. Credentials not stored.${NC}"
        exit 1
    fi
else
    echo -e "${RED}Vault CLI not found or credentials file not available. Credentials not stored.${NC}"
    exit 1
fi

echo -e "${GREEN}Keycloak credentials setup complete!${NC}"
echo -e "${YELLOW}Admin username:${NC} $ADMIN_USER"
echo -e "${YELLOW}Admin password:${NC} $ADMIN_PASSWORD"
echo -e "${YELLOW}Database username:${NC} $DB_USER"
echo -e "${YELLOW}Database password:${NC} $DB_PASSWORD"
echo
echo -e "${YELLOW}Access Keycloak at:${NC} https://login.gray-beard.com" 