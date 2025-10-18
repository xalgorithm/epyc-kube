#!/bin/bash

# Automated Redis Storage Class Fix
# This script automatically fixes the Redis PVC storage class mismatch

set -euo pipefail

NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Automatically fixing Redis storage class issue..."

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

# Check current Redis PVCs
REDIS_PVCS=$(kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o name 2>/dev/null || echo "")

if [[ -z "$REDIS_PVCS" ]]; then
    echo "ℹ️  No Redis PVCs found. Nothing to fix."
    exit 0
fi

echo "📋 Found Redis PVCs with storage class issues:"
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,STORAGE-CLASS:.spec.storageClassName"

# Scale down Redis StatefulSet if it exists
if kubectl get statefulset redis -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "⬇️  Scaling down Redis StatefulSet..."
    kubectl scale statefulset redis -n "$NAMESPACE" --replicas=0
    
    # Wait for pods to be deleted
    echo "⏳ Waiting for Redis pods to be deleted..."
    kubectl wait --for=delete pod -l app.kubernetes.io/name=redis -n "$NAMESPACE" --timeout=120s || true
fi

# Delete existing Redis PVCs
echo "🗑️  Deleting existing Redis PVCs..."
kubectl delete pvc -l app.kubernetes.io/name=redis -n "$NAMESPACE" --ignore-not-found=true

# Wait for PVCs to be fully deleted
echo "⏳ Waiting for PVCs to be fully deleted..."
while kubectl get pvc -l app.kubernetes.io/name=redis -n "$NAMESPACE" >/dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo ""

echo "✅ Old Redis PVCs deleted"

# Apply new storage configuration if it exists
if [[ -f "$SCRIPT_DIR/redis-storage-dynamic.yaml" ]]; then
    echo "📦 Applying new Redis storage configuration..."
    kubectl apply -f "$SCRIPT_DIR/redis-storage-dynamic.yaml"
    echo "✅ New Redis storage configuration applied"
fi

# Scale Redis StatefulSet back up if it existed
if kubectl get statefulset redis -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "⬆️  Scaling Redis StatefulSet back up..."
    kubectl scale statefulset redis -n "$NAMESPACE" --replicas=3
    
    # Wait for pods to be ready
    echo "⏳ Waiting for Redis pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n "$NAMESPACE" --timeout=300s || {
        echo "⚠️  Timeout waiting for Redis pods. Check status manually."
    }
fi

echo ""
echo "✅ Redis storage class issue fixed automatically!"

echo ""
echo "📊 Current Status:"
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis 2>/dev/null || echo "No Redis PVCs found"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis 2>/dev/null || echo "No Redis pods found"

echo ""
echo "🔗 You can now run: ./deploy-redis.sh"