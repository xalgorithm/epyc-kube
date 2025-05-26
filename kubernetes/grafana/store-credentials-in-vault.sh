#!/bin/bash

set -e

echo "Storing Grafana credentials in HashiCorp Vault..."

# Default values (DO NOT MODIFY THESE VALUES AFTER MOVING TO VAULT)
# These will be stored in Vault and then removed from this script
DEFAULT_ADMIN_USER="admin"
DEFAULT_ADMIN_PASSWORD="admin"
DEFAULT_XALG_PASSWORD="admin123."

# Check if vault is installed
if ! command -v vault &> /dev/null; then
    echo "Error: HashiCorp Vault CLI is not installed."
    echo "Please install Vault CLI first: https://www.vaultproject.io/downloads"
    exit 1
fi

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set."
    echo "Example:"
    echo "export VAULT_ADDR=https://vault.example.com:8200"
    echo "export VAULT_TOKEN=hvs.your-vault-token"
    exit 1
fi

# Store Grafana credentials in Vault
echo "Storing Grafana admin credentials in Vault..."
vault kv put secret/grafana/admin \
    username="${DEFAULT_ADMIN_USER}" \
    password="${DEFAULT_ADMIN_PASSWORD}"

echo "Storing Grafana xalg user credentials in Vault..."
vault kv put secret/grafana/xalg \
    username="xalg" \
    password="${DEFAULT_XALG_PASSWORD}"

echo "Creating Kubernetes service account for Vault access..."
kubectl create serviceaccount -n monitoring vault-auth || true

# Create a ClusterRoleBinding for the service account
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: monitoring
EOF

echo "Credentials have been stored in Vault successfully."
echo "Next steps:"
echo "1. Update your scripts to retrieve credentials from Vault using the vault-agent sidecar or Vault API"
echo "2. Remove hardcoded credentials from all scripts and YAML files"
echo "3. Update your Kubernetes manifests to use Vault for secrets management" 