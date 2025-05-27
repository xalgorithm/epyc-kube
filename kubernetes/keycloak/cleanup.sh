#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Keycloak Cleanup Script${NC}"
echo "This script will remove Keycloak and all associated resources from your Kubernetes cluster."
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl could not be found. Please install kubectl first.${NC}"
    exit 1
fi

# Confirm with user
read -p "Are you sure you want to remove Keycloak? This will delete all Keycloak data. (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}Cleanup canceled.${NC}"
    exit 0
fi

# Remove Keycloak resources
echo -e "${BLUE}Removing Keycloak resources...${NC}"

# Delete Ingress
echo -e "${BLUE}Deleting Ingress...${NC}"
kubectl delete -f kubernetes/keycloak/ingress.yaml --ignore-not-found

# Delete Keycloak deployment
echo -e "${BLUE}Deleting Keycloak deployment...${NC}"
kubectl delete -f kubernetes/keycloak/deployment.yaml --ignore-not-found

# Delete PostgreSQL deployment
echo -e "${BLUE}Deleting PostgreSQL deployment...${NC}"
kubectl delete -f kubernetes/keycloak/postgres.yaml --ignore-not-found

# Delete PVCs
echo -e "${BLUE}Deleting persistent volume claims...${NC}"
kubectl delete -f kubernetes/keycloak/pvc.yaml --ignore-not-found

# Delete Secrets
echo -e "${BLUE}Deleting Keycloak secret...${NC}"
kubectl delete -f kubernetes/keycloak/keycloak-secret.yaml --ignore-not-found

# Ask if they want to remove the namespace
read -p "Do you want to remove the Keycloak namespace as well? (y/n): " REMOVE_NS
if [[ "$REMOVE_NS" == "y" || "$REMOVE_NS" == "Y" ]]; then
    echo -e "${BLUE}Deleting Keycloak namespace...${NC}"
    kubectl delete -f kubernetes/keycloak/namespace.yaml --ignore-not-found
fi

# Check if Vault is accessible and ask about removing Vault secrets
if [ -f ~/.vault/credentials ] && command -v vault &> /dev/null; then
    read -p "Do you want to remove Keycloak credentials from Vault? (y/n): " REMOVE_VAULT
    if [[ "$REMOVE_VAULT" == "y" || "$REMOVE_VAULT" == "Y" ]]; then
        echo -e "${BLUE}Removing Keycloak credentials from Vault...${NC}"
        
        # Source Vault credentials
        source ~/.vault/credentials
        
        # Set Vault address
        export VAULT_ADDR=${VAULT_ADDR:-"https://vault.gray-beard.com"}
        
        # Try to log in with root token
        if [ -n "$VAULT_ROOT_TOKEN" ]; then
            echo -e "${BLUE}Logging into Vault...${NC}"
            if vault login "$VAULT_ROOT_TOKEN" &> /dev/null; then
                # Delete Keycloak secret from Vault
                echo -e "${BLUE}Deleting Keycloak secret from Vault...${NC}"
                vault kv delete secret/keycloak
                
                echo -e "${GREEN}Successfully removed Keycloak credentials from Vault!${NC}"
            else
                echo -e "${RED}Could not log in to Vault with stored token. Vault credentials not removed.${NC}"
            fi
        else
            echo -e "${RED}No Vault root token found. Vault credentials not removed.${NC}"
        fi
    fi
fi

echo -e "${GREEN}Keycloak cleanup complete!${NC}" 