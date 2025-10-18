#!/bin/bash

# Fix Redis Storage Class Issue
# This script fixes the Redis PVC storage class mismatch by recreating the PVCs

set -euo pipefail

NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🔧 Fixing Redis Storage Class Issue..."

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

# Check current Redis PVCs
log_info "Checking current Redis PVCs..."
REDIS_PVCS=$(kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o name 2>/dev/null || echo "")

if [[ -z "$REDIS_PVCS" ]]; then
    log_info "No Redis PVCs found. This is normal for a fresh deployment."
    exit 0
fi

echo "Found Redis PVCs:"
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis

# Check if Redis StatefulSet exists
log_info "Checking Redis StatefulSet..."
if kubectl get statefulset redis -n "$NAMESPACE" >/dev/null 2>&1; then
    log_warning "Redis StatefulSet exists. We need to scale it down first."
    
    # Scale down Redis StatefulSet
    log_info "Scaling down Redis StatefulSet to 0 replicas..."
    kubectl scale statefulset redis -n "$NAMESPACE" --replicas=0
    
    # Wait for pods to be deleted
    log_info "Waiting for Redis pods to be deleted..."
    kubectl wait --for=delete pod -l app.kubernetes.io/name=redis -n "$NAMESPACE" --timeout=120s || true
    
    log_success "Redis StatefulSet scaled down"
else
    log_info "No Redis StatefulSet found"
fi

# Get list of Redis PVCs to delete
REDIS_PVC_NAMES=$(kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[*].metadata.name}')

if [[ -n "$REDIS_PVC_NAMES" ]]; then
    log_warning "The following Redis PVCs will be deleted:"
    for pvc in $REDIS_PVC_NAMES; do
        echo "  - $pvc"
    done
    
    echo ""
    log_warning "⚠️  WARNING: This will delete all Redis data!"
    log_warning "⚠️  Make sure you have backups if needed."
    echo ""
    
    read -p "Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    # Delete Redis PVCs
    log_info "Deleting Redis PVCs..."
    for pvc in $REDIS_PVC_NAMES; do
        log_info "Deleting PVC: $pvc"
        kubectl delete pvc "$pvc" -n "$NAMESPACE" --ignore-not-found=true
    done
    
    # Wait for PVCs to be fully deleted
    log_info "Waiting for PVCs to be fully deleted..."
    for pvc in $REDIS_PVC_NAMES; do
        while kubectl get pvc "$pvc" -n "$NAMESPACE" >/dev/null 2>&1; do
            echo -n "."
            sleep 2
        done
    done
    echo ""
    
    log_success "All Redis PVCs deleted"
else
    log_info "No Redis PVCs to delete"
fi

# Now apply the new storage configuration
log_info "Applying new Redis storage configuration..."
if [[ -f "$SCRIPT_DIR/redis-storage-dynamic.yaml" ]]; then
    kubectl apply -f "$SCRIPT_DIR/redis-storage-dynamic.yaml"
    log_success "New Redis storage configuration applied"
else
    log_error "redis-storage-dynamic.yaml not found"
    exit 1
fi

# Wait for new PVCs to be bound
log_info "Waiting for new Redis PVCs to be bound..."
sleep 5

# Check PVC status
NEW_PVCS=$(kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o name 2>/dev/null || echo "")
if [[ -n "$NEW_PVCS" ]]; then
    kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis
    
    # Wait for all PVCs to be bound
    log_info "Waiting for PVCs to be bound..."
    kubectl wait --for=condition=bound pvc -l app.kubernetes.io/name=redis -n "$NAMESPACE" --timeout=300s
    
    log_success "New Redis PVCs are bound"
else
    log_warning "No new Redis PVCs found. They may be created by the StatefulSet."
fi

# Scale Redis StatefulSet back up if it existed
if kubectl get statefulset redis -n "$NAMESPACE" >/dev/null 2>&1; then
    log_info "Scaling Redis StatefulSet back up..."
    kubectl scale statefulset redis -n "$NAMESPACE" --replicas=3
    
    # Wait for pods to be ready
    log_info "Waiting for Redis pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n "$NAMESPACE" --timeout=300s
    
    log_success "Redis StatefulSet scaled back up"
fi

echo ""
log_success "✅ Redis storage class issue fixed!"

echo ""
log_info "📊 Current Redis Storage Status:"
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis
echo ""
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis

echo ""
log_info "🔗 Next Steps:"
echo "1. Verify Redis is working: kubectl exec -n $NAMESPACE redis-0 -- redis-cli ping"
echo "2. Check Redis cluster status: kubectl exec -n $NAMESPACE redis-0 -- redis-cli cluster nodes"
echo "3. Continue with your deployment: ./deploy-redis.sh"