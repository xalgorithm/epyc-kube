#!/bin/bash

# Setup PostgreSQL Exporter Credentials
# This script configures PostgreSQL exporter with proper database credentials
# Requirements: 3.1, 3.7 - Configure PostgreSQL exporter with proper credentials

set -euo pipefail

NAMESPACE="airflow"
VAULT_PATH="airflow/database"

echo "🔐 Setting up PostgreSQL Exporter Credentials..."

# Check if Vault CLI is available
if ! command -v vault &> /dev/null; then
    echo "❌ Vault CLI not found. Please install vault CLI first."
    exit 1
fi

# Check if we can access Vault
if ! vault status >/dev/null 2>&1; then
    echo "❌ Cannot access Vault. Please ensure Vault is accessible and you are authenticated."
    exit 1
fi

# Get database credentials from Vault
echo "📥 Retrieving database credentials from Vault..."

DB_USER=$(vault kv get -field=username "$VAULT_PATH" 2>/dev/null || echo "")
DB_PASSWORD=$(vault kv get -field=password "$VAULT_PATH" 2>/dev/null || echo "")
DB_HOST="postgresql-primary"
DB_PORT="5432"
DB_NAME="airflow"

if [[ -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
    echo "❌ Could not retrieve database credentials from Vault path: $VAULT_PATH"
    echo "Please ensure the credentials are stored in Vault with keys 'username' and 'password'"
    exit 1
fi

# Create the connection string
CONNECTION_STRING="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=disable"

echo "🔄 Updating PostgreSQL exporter secret..."

# Update the secret
kubectl create secret generic postgresql-exporter-secret \
    --from-literal=DATA_SOURCE_NAME="$CONNECTION_STRING" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ PostgreSQL exporter credentials updated successfully!"

# Restart the exporter to pick up new credentials
echo "🔄 Restarting PostgreSQL exporter..."
kubectl rollout restart deployment/postgresql-exporter -n "$NAMESPACE"

# Wait for rollout to complete
echo "⏳ Waiting for PostgreSQL exporter to restart..."
kubectl rollout status deployment/postgresql-exporter -n "$NAMESPACE" --timeout=120s

echo "✅ PostgreSQL exporter restarted successfully!"

echo ""
echo "🔍 Verification:"
echo "kubectl logs -n $NAMESPACE deployment/postgresql-exporter"
echo "kubectl port-forward -n $NAMESPACE service/postgresql-exporter 9187:9187"
echo "curl http://localhost:9187/metrics | grep pg_"