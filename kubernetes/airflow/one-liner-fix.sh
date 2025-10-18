#!/bin/bash

# One-liner fix for PostgreSQL storage issue
echo "🔧 One-liner PostgreSQL storage fix..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delete everything and recreate with nfs-client
kubectl delete pvc postgresql-primary-pvc postgresql-standby-pvc -n airflow --ignore-not-found=true && \
sleep 5 && \
kubectl apply -f "$SCRIPT_DIR/postgresql-storage-simple.yaml" && \
echo "✅ PVCs recreated with nfs-client storage class!"