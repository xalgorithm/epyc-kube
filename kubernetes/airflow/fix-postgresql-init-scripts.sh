#!/bin/bash

# Fix PostgreSQL Initialization Scripts
# This script fixes the syntax errors in PostgreSQL init scripts and restarts the pods

set -euo pipefail

NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Fixing PostgreSQL Initialization Scripts..."

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

echo "📝 Updating PostgreSQL ConfigMap..."
kubectl apply -f "$SCRIPT_DIR/postgresql-configmap.yaml"

echo "🔄 Restarting PostgreSQL pods to pick up new configuration..."

# Delete existing pods to force recreation with new config
echo "Deleting PostgreSQL primary pod..."
kubectl delete pod -n "$NAMESPACE" -l app=postgresql,component=primary --ignore-not-found=true

echo "Deleting PostgreSQL standby pod..."
kubectl delete pod -n "$NAMESPACE" -l app=postgresql,component=standby --ignore-not-found=true

echo "⏳ Waiting for PostgreSQL primary to be ready..."
kubectl wait --for=condition=ready --timeout=300s pod -n "$NAMESPACE" -l app=postgresql,component=primary

echo "⏳ Waiting for PostgreSQL standby to be ready..."
if kubectl get pod -n "$NAMESPACE" -l app=postgresql,component=standby >/dev/null 2>&1; then
    kubectl wait --for=condition=ready --timeout=300s pod -n "$NAMESPACE" -l app=postgresql,component=standby
else
    echo "ℹ️  No standby pod found - this is normal if standby hasn't been deployed yet"
fi

echo "✅ PostgreSQL initialization scripts fixed and pods restarted!"

echo ""
echo "🔍 Verification Commands:"
echo "kubectl logs -n $NAMESPACE -l app=postgresql,component=primary"
echo "kubectl logs -n $NAMESPACE -l app=postgresql,component=standby"
echo "kubectl exec -n $NAMESPACE -it \$(kubectl get pod -n $NAMESPACE -l app=postgresql,component=primary -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -d airflow -c '\\l'"

echo ""
echo "📊 Check Database Status:"
echo "kubectl exec -n $NAMESPACE -it \$(kubectl get pod -n $NAMESPACE -l app=postgresql,component=primary -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -d postgres -c 'SELECT * FROM pg_stat_replication;'"