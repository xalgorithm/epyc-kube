#!/bin/bash

# Quick fix for PostgreSQL storage binding issues
# Uses existing nfs-client storage class for immediate resolution

set -euo pipefail

NAMESPACE="airflow"

echo "🔧 Quick fix for PostgreSQL storage binding issues..."

# Delete the problematic StatefulSet and PVCs
echo "Cleaning up existing resources..."
kubectl delete statefulset postgresql-primary -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-data-postgresql-primary-0 -n "$NAMESPACE" --ignore-not-found=true

# Wait for cleanup
echo "Waiting for cleanup..."
sleep 10

# Apply the simple storage configuration
echo "Applying corrected storage configuration..."
kubectl apply -f kubernetes/airflow/postgresql-storage-simple.yaml

# Wait for PVCs to bind
echo "Waiting for PVCs to bind..."
kubectl wait --for=condition=Bound pvc/postgresql-primary-pvc -n "$NAMESPACE" --timeout=60s
kubectl wait --for=condition=Bound pvc/postgresql-standby-pvc -n "$NAMESPACE" --timeout=60s

# Deploy PostgreSQL primary with corrected storage class
echo "Deploying PostgreSQL primary..."
kubectl apply -f kubernetes/airflow/postgresql-primary.yaml

echo "✅ Quick fix applied! PostgreSQL should now deploy successfully."
echo "Monitor with: kubectl get pods -n $NAMESPACE -w"