#!/bin/bash

# Fix PostgreSQL storage by handling immutable StorageClass fields
# Deletes existing StorageClass and recreates with correct configuration

set -euo pipefail

NAMESPACE="airflow"

echo "🔧 Fixing PostgreSQL storage with immutable StorageClass handling..."

# Step 1: Clean up existing resources that depend on the StorageClass
echo "Step 1: Cleaning up dependent resources..."
kubectl delete statefulset postgresql-primary -n "$NAMESPACE" --ignore-not-found=true
kubectl delete statefulset postgresql-standby -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-data-postgresql-primary-0 -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-data-postgresql-standby-0 -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-primary-pvc -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-standby-pvc -n "$NAMESPACE" --ignore-not-found=true

# Step 2: Delete the problematic StorageClass
echo "Step 2: Deleting existing StorageClass..."
kubectl delete storageclass postgresql-storage --ignore-not-found=true

# Step 3: Wait for cleanup
echo "Step 3: Waiting for cleanup to complete..."
sleep 10

# Step 4: Apply the simple storage configuration (just PVCs using nfs-client)
echo "Step 4: Creating PVCs with nfs-client storage class..."
kubectl apply -f kubernetes/airflow/postgresql-storage-simple.yaml

# Step 5: Wait for PVCs to bind
echo "Step 5: Waiting for PVCs to bind..."
kubectl wait --for=condition=Bound pvc/postgresql-primary-pvc -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=Bound pvc/postgresql-standby-pvc -n "$NAMESPACE" --timeout=120s

echo "✅ Storage configuration fixed!"
echo "📋 PVC Status:"
kubectl get pvc -n "$NAMESPACE" | grep postgresql

echo ""
echo "🚀 Now you can deploy PostgreSQL:"
echo "kubectl apply -f kubernetes/airflow/postgresql-primary.yaml"
echo "kubectl apply -f kubernetes/airflow/postgresql-standby.yaml"