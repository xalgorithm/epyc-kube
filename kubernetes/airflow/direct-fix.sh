#!/bin/bash

# Direct fix for PostgreSQL storage - no external file dependencies
echo "🔧 Direct PostgreSQL storage fix..."

NAMESPACE="airflow"

# Delete the problematic PVCs
echo "Deleting problematic PVCs..."
kubectl delete pvc postgresql-primary-pvc postgresql-standby-pvc -n "$NAMESPACE" --ignore-not-found=true

# Wait for deletion
echo "Waiting for deletion..."
sleep 10

# Create new PVCs directly with nfs-client
echo "Creating new PVCs with nfs-client storage class..."
kubectl apply -f - <<EOF
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

# Wait for binding
echo "Waiting for PVCs to bind..."
kubectl wait --for=condition=Bound pvc/postgresql-primary-pvc -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=Bound pvc/postgresql-standby-pvc -n "$NAMESPACE" --timeout=120s

echo "✅ PVCs created and bound successfully!"
echo "📋 PVC Status:"
kubectl get pvc -n "$NAMESPACE" | grep postgresql

echo ""
echo "🚀 Now deploy PostgreSQL:"
echo "kubectl apply -f kubernetes/airflow/postgresql-primary.yaml"