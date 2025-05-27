#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}n8n Credentials Reset Script${NC}"
echo "This script will reset the n8n credentials in both Kubernetes and Vault."
echo

# Set default credentials if not provided
DEFAULT_EMAIL="admin@example.com"
DEFAULT_PASSWORD="NewPassword123!"

# Get user input for new credentials
read -p "Enter email address (default: admin@example.com): " EMAIL
EMAIL=${EMAIL:-$DEFAULT_EMAIL}

# Validate email format
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Invalid email format. Please use a valid email address.${NC}"
    exit 1
fi

read -s -p "Enter new password (default: NewPassword123!): " PASSWORD
PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
echo

# Base64 encode credentials for Kubernetes secret
EMAIL_B64=$(echo -n "$EMAIL" | base64)
PASSWORD_B64=$(echo -n "$PASSWORD" | base64)

# Update the secret file with the new credentials
echo -e "${BLUE}Updating secret file with new credentials...${NC}"
sed -i '' "s/N8N_BASIC_AUTH_USER: .*$/N8N_BASIC_AUTH_USER: $EMAIL_B64  # $EMAIL/" kubernetes/n8n/reset-credentials.yaml
sed -i '' "s/N8N_BASIC_AUTH_PASSWORD: .*$/N8N_BASIC_AUTH_PASSWORD: $PASSWORD_B64  # $PASSWORD/" kubernetes/n8n/reset-credentials.yaml

# Apply the updated secret to Kubernetes
echo -e "${BLUE}Applying updated secret to Kubernetes...${NC}"
kubectl apply -f kubernetes/n8n/reset-credentials.yaml

# Check if we can access Vault to update credentials there as well
if [ -f ~/.vault/credentials ] && command -v vault &> /dev/null; then
    echo -e "${BLUE}Updating credentials in Vault...${NC}"
    
    # Source Vault credentials
    source ~/.vault/credentials
    
    # Set Vault address
    export VAULT_ADDR=${VAULT_ADDR:-"https://vault.gray-beard.com"}
    
    # Try to log in with root token
    if [ -n "$VAULT_ROOT_TOKEN" ]; then
        echo -e "${BLUE}Logging into Vault...${NC}"
        if vault login "$VAULT_ROOT_TOKEN" &> /dev/null; then
            # Update n8n secret in Vault
            echo -e "${BLUE}Updating n8n secret in Vault...${NC}"
            vault kv put secret/n8n \
                admin_user="$EMAIL" \
                admin_password="$PASSWORD" \
                db_type="sqlite" \
                db_sqlite_path="/home/node/.n8n/database.sqlite" \
                metrics_enabled="true" \
                runners_enabled="true"
            
            echo -e "${GREEN}Successfully updated credentials in Vault!${NC}"
        else
            echo -e "${YELLOW}Could not log in to Vault with stored token. Vault credentials not updated.${NC}"
        fi
    else
        echo -e "${YELLOW}No Vault root token found. Vault credentials not updated.${NC}"
    fi
else
    echo -e "${YELLOW}Vault CLI not found or credentials file not available. Vault credentials not updated.${NC}"
fi

# Restart the n8n pod to apply the changes
echo -e "${BLUE}Restarting n8n pod to apply new credentials...${NC}"
kubectl rollout restart deployment n8n -n n8n

# Wait for the pod to restart
echo -e "${BLUE}Waiting for n8n pod to restart...${NC}"
kubectl rollout status deployment n8n -n n8n

echo -e "${GREEN}n8n credentials have been reset successfully!${NC}"
echo -e "${YELLOW}New credentials:${NC}"
echo -e "Email: ${BLUE}$EMAIL${NC}"
echo -e "Password: ${BLUE}$PASSWORD${NC}"
echo
echo -e "${YELLOW}Access n8n at:${NC} https://automate.gray-beard.com" 