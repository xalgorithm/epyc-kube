#!/bin/bash

# Simple PostgreSQL storage fix - bypass custom StorageClass entirely
# Uses existing nfs-client storage class directly

set -euo pipefail

NAMESPACE="airflow"

echo "🔧 Simple PostgreSQL storage fix..."

# Clean up any existing problematic resources
echo "Cleaning up existing resources..."
kubectl delete statefulset postgresql-primary -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-data-postgresql-primary-0 -n "$NAMESPACE" --ignore-not-found=true

# Wait for cleanup
sleep 5

# Create PVCs directly with nfs-client (skip the custom StorageClass)
echo "Creating PVCs with nfs-client storage class..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-primary-pvc
  namespace: $NAMESPACE
  labels:
    app: postgresql
    component: primary
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-client
  resources:
    requests:
      storage: 100Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-standby-pvc
  namespace: $NAMESPACE
  labels:
    app: postgresql
    component: standby
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-client
  resources:
    requests:
      storage: 100Gi
EOF

# Wait for PVCs to bind
echo "Waiting for PVCs to bind..."
kubectl wait --for=condition=Bound pvc/postgresql-primary-pvc -n "$NAMESPACE" --timeout=60s
kubectl wait --for=condition=Bound pvc/postgresql-standby-pvc -n "$NAMESPACE" --timeout=60s

# Deploy PostgreSQL primary (it should now find the bound PVC)
echo "Deploying PostgreSQL primary..."
kubectl apply -f kubernetes/airflow/postgresql-primary.yaml

echo "✅ PostgreSQL deployment started!"
echo "Monitor with: kubectl get pods -n $NAMESPACE -w"
echo "Check PVCs: kubectl get pvc -n $NAMESPACE"