#!/bin/bash

# Final PostgreSQL storage fix - handles all immutable resource issues
# Completely cleans up and recreates everything with correct storage class

set -euo pipefail

NAMESPACE="airflow"

echo "🔧 Final PostgreSQL storage fix - handling all immutable resources..."

# Step 1: Stop all PostgreSQL workloads
echo "Step 1: Stopping PostgreSQL workloads..."
kubectl delete statefulset postgresql-primary -n "$NAMESPACE" --ignore-not-found=true
kubectl delete statefulset postgresql-standby -n "$NAMESPACE" --ignore-not-found=true

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=postgresql -n "$NAMESPACE" --timeout=120s || true

# Step 2: Delete ALL existing PVCs (they have immutable storageClassName)
echo "Step 2: Deleting all existing PVCs..."
kubectl delete pvc postgresql-primary-pvc -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-standby-pvc -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-data-postgresql-primary-0 -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc postgresql-data-postgresql-standby-0 -n "$NAMESPACE" --ignore-not-found=true

# Step 3: Delete the problematic StorageClass
echo "Step 3: Deleting problematic StorageClass..."
kubectl delete storageclass postgresql-storage --ignore-not-found=true

# Step 4: Wait for complete cleanup
echo "Step 4: Waiting for complete cleanup..."
sleep 15

# Step 5: Verify cleanup
echo "Step 5: Verifying cleanup..."
echo "Remaining PostgreSQL resources:"
kubectl get all,pvc,pv -n "$NAMESPACE" -l app=postgresql || echo "No PostgreSQL resources found (good!)"

# Step 6: Create fresh PVCs with nfs-client
echo "Step 6: Creating fresh PVCs with nfs-client storage class..."
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

# Step 7: Wait for PVCs to bind
echo "Step 7: Waiting for PVCs to bind..."
echo "This may take a moment with NFS provisioning..."

# Wait for primary PVC
echo -n "Waiting for postgresql-primary-pvc to bind..."
while [[ "$(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Bound" ]]; do
    echo -n "."
    sleep 2
done
echo " ✅ Bound!"

# Wait for standby PVC
echo -n "Waiting for postgresql-standby-pvc to bind..."
while [[ "$(kubectl get pvc postgresql-standby-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Bound" ]]; do
    echo -n "."
    sleep 2
done
echo " ✅ Bound!"

# Step 8: Show PVC status
echo "Step 8: PVC Status:"
kubectl get pvc -n "$NAMESPACE" | grep postgresql

# Step 9: Deploy PostgreSQL primary
echo "Step 9: Deploying PostgreSQL primary..."
kubectl apply -f kubernetes/airflow/postgresql-primary.yaml

# Step 10: Wait for primary to be ready
echo "Step 10: Waiting for PostgreSQL primary to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql,component=primary -n "$NAMESPACE" --timeout=300s

echo ""
echo "✅ PostgreSQL storage issue completely resolved!"
echo "🎉 PostgreSQL primary is now running with proper NFS storage!"
echo ""
echo "📋 Status:"
kubectl get pods,pvc -n "$NAMESPACE" -l app=postgresql

echo ""
echo "🚀 Next steps:"
echo "1. Deploy standby: kubectl apply -f kubernetes/airflow/postgresql-standby.yaml"
echo "2. Test connection: kubectl exec -n $NAMESPACE postgresql-primary-0 -- pg_isready"
echo "3. Proceed with Airflow deployment"