#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VAULT_PASSWORD=${VAULT_PASSWORD:-"changeme"}
VAULT_DOMAIN=${VAULT_DOMAIN:-"vault.gray-beard.com"}

echo "Deploying HashiCorp Vault..."

# Deploy Vault resources
kubectl apply -f vault-config.yaml
kubectl apply -f vault-ingress.yaml

# Wait for Vault to become ready
echo "Waiting for Vault pod to be ready..."
kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=120s

# Set up port forwarding for initialization
echo "Setting up port forwarding to Vault..."
kubectl port-forward svc/vault -n vault 8200:8200 &
FORWARDING_PID=$!

# Wait for port forwarding to establish
sleep 5

# Initialize Vault
echo "Initializing Vault..."
INIT_RESPONSE=$(curl -s \
    --request POST \
    --data '{"secret_shares": 1, "secret_threshold": 1}' \
    http://127.0.0.1:8200/v1/sys/init)

# Extract root token and unseal key
UNSEAL_KEY=$(echo $INIT_RESPONSE | jq -r .keys[0])
ROOT_TOKEN=$(echo $INIT_RESPONSE | jq -r .root_token)

# Store the unseal key and root token securely
echo "Storing Vault credentials..."
mkdir -p ~/.vault
echo "VAULT_UNSEAL_KEY=$UNSEAL_KEY" > ~/.vault/credentials
echo "VAULT_ROOT_TOKEN=$ROOT_TOKEN" >> ~/.vault/credentials
chmod 600 ~/.vault/credentials

# Unseal the vault
echo "Unsealing Vault..."
curl -s \
    --request POST \
    --data "{\"key\": \"$UNSEAL_KEY\"}" \
    http://127.0.0.1:8200/v1/sys/unseal

# Create a Policy for managing secrets
echo "Creating Vault policies..."
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request PUT \
    --data '{"policy": "path \"secret/*\" {capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\"]}"}' \
    http://127.0.0.1:8200/v1/sys/policies/acl/secrets-manager

# Create service account for K8s auth
kubectl create serviceaccount vault-auth -n vault || true

# Create approle for programmatic access
echo "Setting up AppRole authentication..."
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    http://127.0.0.1:8200/v1/sys/auth/approle \
    --data '{"type": "approle"}'

# Create named role
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data "{\"policies\": [\"secrets-manager\"], \"token_ttl\": \"1h\", \"token_max_ttl\": \"4h\"}" \
    http://127.0.0.1:8200/v1/auth/approle/role/k8s-secrets

# Get role ID
ROLE_ID=$(curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    http://127.0.0.1:8200/v1/auth/approle/role/k8s-secrets/role-id | jq -r .data.role_id)

# Get secret ID
SECRET_ID=$(curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    http://127.0.0.1:8200/v1/auth/approle/role/k8s-secrets/secret-id | jq -r .data.secret_id)

# Store AppRole credentials
echo "VAULT_ROLE_ID=$ROLE_ID" >> ~/.vault/credentials
echo "VAULT_SECRET_ID=$SECRET_ID" >> ~/.vault/credentials

# Store app-specific secrets
echo "Storing application secrets in Vault..."

# Set up secret engine if it doesn't exist
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data '{"type": "kv", "options": {"version": "2"}}' \
    http://127.0.0.1:8200/v1/sys/mounts/secret || true

# Store alertmanager secret
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data "{\"data\": {\"smtp_host\": \"smtp.gmail.com:587\", \"smtp_from\": \"admin@example.com\", \"smtp_username\": \"admin@example.com\", \"smtp_password\": \"${SMTP_PASSWORD:-'app-password-here'}\", \"recipient_email\": \"admin@example.com\"}}" \
    http://127.0.0.1:8200/v1/secret/data/alertmanager

# Store n8n secret
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data "{\"data\": {\"admin_user\": \"admin\", \"admin_password\": \"$VAULT_PASSWORD\", \"db_type\": \"sqlite\", \"db_sqlite_path\": \"/home/node/.n8n/database.sqlite\", \"metrics_enabled\": \"true\", \"runners_enabled\": \"true\"}}" \
    http://127.0.0.1:8200/v1/secret/data/n8n

# Store couchdb secret
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data "{\"data\": {\"username\": \"xalg\", \"password\": \"$VAULT_PASSWORD\", \"secret_cookie\": \"obsidian-sync-cookie-$(openssl rand -hex 8)\"}}" \
    http://127.0.0.1:8200/v1/secret/data/couchdb

# Store K3s token
curl -s \
    --header "X-Vault-Token: $ROOT_TOKEN" \
    --request POST \
    --data "{\"data\": {\"token\": \"$(openssl rand -hex 16)\"}}" \
    http://127.0.0.1:8200/v1/secret/data/k3s

# Kill the port forwarding process
kill $FORWARDING_PID

# Create the vault credentials secret for applications
kubectl create secret generic vault-credentials -n vault \
  --from-literal=role_id=$ROLE_ID \
  --from-literal=secret_id=$SECRET_ID

echo ""
echo "HashiCorp Vault has been successfully deployed and configured."
echo "Vault UI is available at: https://$VAULT_DOMAIN"
echo ""
echo "Vault credentials have been stored in ~/.vault/credentials"
echo "These credentials should be kept secure and backed up safely."
echo ""
echo "Initial root password was set (check script for default or use VAULT_PASSWORD env var)"
echo ""
echo "Run: source ~/.vault/credentials"
echo "to load Vault environment variables in your current shell." 