#!/bin/bash

# Deploy PostgreSQL with existing bound PVCs
# Skips storage creation since PVCs are already bound and working

set -euo pipefail

NAMESPACE="airflow"

echo "🚀 Deploying PostgreSQL with existing bound storage..."

# Check if PVCs are bound
echo "Checking PVC status..."
kubectl get pvc -n "$NAMESPACE" | grep postgresql

primary_status=$(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')
standby_status=$(kubectl get pvc postgresql-standby-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')

if [[ "$primary_status" != "Bound" || "$standby_status" != "Bound" ]]; then
    echo "❌ PVCs are not bound. Please run the storage fix first."
    exit 1
fi

echo "✅ PVCs are bound and ready!"

# Deploy PostgreSQL primary (skip storage creation)
echo "Deploying PostgreSQL primary..."
kubectl apply -f kubernetes/airflow/postgresql-primary.yaml

# Wait for primary to be ready
echo "Waiting for PostgreSQL primary to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql,component=primary -n "$NAMESPACE" --timeout=300s

echo "✅ PostgreSQL primary is running!"

# Deploy PostgreSQL standby
echo "Deploying PostgreSQL standby..."
kubectl apply -f kubernetes/airflow/postgresql-standby.yaml

# Wait for standby to be ready
echo "Waiting for PostgreSQL standby to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql,component=standby -n "$NAMESPACE" --timeout=300s

echo "✅ PostgreSQL standby is running!"

# Show final status
echo ""
echo "📋 Final Status:"
kubectl get pods,pvc,svc -n "$NAMESPACE" -l app=postgresql

echo ""
echo "🎉 PostgreSQL deployment completed successfully!"
echo ""
echo "🔍 Test connection:"
echo "kubectl exec -n $NAMESPACE postgresql-primary-0 -- pg_isready -U postgres"
echo ""
echo "🚀 Next: Deploy Airflow with the working PostgreSQL database!"