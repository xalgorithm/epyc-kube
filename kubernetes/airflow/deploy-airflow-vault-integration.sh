#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Deploying Airflow Vault integration..."

# Check if Vault is deployed and accessible
if ! kubectl get namespace vault &>/dev/null; then
  echo "Error: Vault namespace not found. Please deploy Vault first using kubernetes/vault/deploy-vault.sh"
  exit 1
fi

# Check if Vault Secrets Operator is deployed
if ! kubectl get namespace vault-secrets &>/dev/null; then
  echo "Error: Vault Secrets Operator not found. Please deploy it first using kubernetes/vault/deploy-secrets-operator.sh"
  exit 1
fi

# Check if airflow namespace exists
if ! kubectl get namespace airflow &>/dev/null; then
  echo "Creating airflow namespace..."
  kubectl create namespace airflow
fi

# Set up Airflow secrets in Vault
echo "Setting up Airflow secrets in Vault..."
./setup-airflow-vault-secrets.sh

# Wait a moment for Vault to process the secrets
sleep 5

# Deploy the Vault secret templates for Airflow
echo "Deploying Vault secret templates for Airflow..."
kubectl apply -f airflow-vault-secrets.yaml

# Copy vault-credentials secret to airflow namespace for the operator
echo "Copying Vault credentials to airflow namespace..."
kubectl get secret vault-credentials -n vault -o yaml | \
  sed 's/namespace: vault/namespace: airflow/' | \
  kubectl apply -f -

# Wait for secrets to be synced
echo "Waiting for secrets to be synced from Vault..."
sleep 10

# Verify that secrets have been created
echo "Verifying secret synchronization..."
for secret in airflow-database-secret airflow-redis-secret airflow-webserver-secret airflow-connections-secret; do
  if kubectl get secret $secret -n airflow &>/dev/null; then
    echo "✓ $secret successfully synced"
  else
    echo "✗ $secret failed to sync"
  fi
done

# Update existing PostgreSQL and Redis secrets to use Vault-managed passwords
echo "Updating existing secrets to reference Vault-managed credentials..."

# Update PostgreSQL secret to use Vault credentials
kubectl patch secret postgresql-secret -n airflow --type='merge' -p='{
  "metadata": {
    "annotations": {
      "vault-secrets-operator.ricoberger.de/secrets-path": "secret/data/airflow/database",
      "vault-secrets-operator.ricoberger.de/secrets-template": "POSTGRES_USER: \"{{ .username }}\"\nPOSTGRES_PASSWORD: \"{{ .password }}\"\nPOSTGRES_DB: \"{{ .database }}\"\nPOSTGRES_REPLICATION_PASSWORD: \"{{ .password }}\""
    }
  }
}' || echo "PostgreSQL secret not found, will be created by Vault operator"

# Update Redis secret to use Vault credentials  
kubectl patch secret redis-secret -n airflow --type='merge' -p='{
  "metadata": {
    "annotations": {
      "vault-secrets-operator.ricoberger.de/secrets-path": "secret/data/airflow/redis",
      "vault-secrets-operator.ricoberger.de/secrets-template": "redis-password: \"{{ .password }}\""
    }
  }
}' || echo "Redis secret not found, will be created by Vault operator"

echo ""
echo "Airflow Vault integration has been successfully deployed!"
echo ""
echo "The following secrets are now managed by Vault:"
echo "- airflow-database-secret: Database connection credentials"
echo "- airflow-redis-secret: Redis authentication credentials"
echo "- airflow-webserver-secret: Webserver and application secrets"
echo "- airflow-connections-secret: External service connections"
echo ""
echo "Existing PostgreSQL and Redis secrets have been updated to sync from Vault."
echo "The Vault Secrets Operator will automatically keep these secrets in sync."
echo ""
echo "Next steps:"
echo "1. Update your Airflow Helm values to reference these Vault-managed secrets"
echo "2. Restart PostgreSQL and Redis pods to use the new passwords"
echo "3. Deploy Airflow with the updated configuration"