#!/bin/bash

# Fix PostgreSQL Storage Issues
# This script resolves PVC binding problems by cleaning up and redeploying storage resources

set -euo pipefail

# Configuration
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

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    
    if [[ -n "$namespace" ]]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
    else
        kubectl get "$resource_type" "$resource_name" >/dev/null 2>&1
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    local timeout="${4:-60}"
    
    log_info "Waiting for $resource_type/$resource_name to be deleted..."
    local count=0
    while resource_exists "$resource_type" "$resource_name" "$namespace"; do
        if [[ $count -ge $timeout ]]; then
            log_error "Timeout waiting for $resource_type/$resource_name deletion"
            return 1
        fi
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo
    log_success "$resource_type/$resource_name deleted successfully"
}

# Function to check storage classes
check_storage_classes() {
    log_info "Checking available storage classes..."
    
    if kubectl get storageclass nfs-client >/dev/null 2>&1; then
        log_success "✓ NFS storage class available"
        return 0
    elif kubectl get storageclass local-path >/dev/null 2>&1; then
        log_warning "⚠ Using local-path storage (NFS preferred for production)"
        return 1
    else
        log_error "✗ No suitable storage class found"
        return 2
    fi
}

# Function to clean up existing resources
cleanup_existing_resources() {
    log_info "Cleaning up existing PostgreSQL resources..."
    
    # Stop PostgreSQL StatefulSets first
    if resource_exists statefulset postgresql-primary "$NAMESPACE"; then
        log_info "Scaling down PostgreSQL primary..."
        kubectl scale statefulset postgresql-primary --replicas=0 -n "$NAMESPACE"
        kubectl wait --for=delete pod -l app=postgresql,component=primary -n "$NAMESPACE" --timeout=120s || true
    fi
    
    if resource_exists statefulset postgresql-standby "$NAMESPACE"; then
        log_info "Scaling down PostgreSQL standby..."
        kubectl scale statefulset postgresql-standby --replicas=0 -n "$NAMESPACE"
        kubectl wait --for=delete pod -l app=postgresql,component=standby -n "$NAMESPACE" --timeout=120s || true
    fi
    
    # Delete StatefulSets
    kubectl delete statefulset postgresql-primary -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete statefulset postgresql-standby -n "$NAMESPACE" --ignore-not-found=true
    
    # Delete problematic PVCs
    kubectl delete pvc postgresql-data-postgresql-primary-0 -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete pvc postgresql-data-postgresql-standby-0 -n "$NAMESPACE" --ignore-not-found=true
    
    # Delete old PVs if they exist
    kubectl delete pv postgresql-primary-pv --ignore-not-found=true
    kubectl delete pv postgresql-standby-pv --ignore-not-found=true
    
    # Wait a moment for cleanup
    sleep 5
    log_success "Cleanup completed"
}

# Function to deploy storage configuration
deploy_storage() {
    log_info "Deploying PostgreSQL storage configuration..."
    
    # Apply storage configuration
    kubectl apply -f "$SCRIPT_DIR/postgresql-storage.yaml"
    log_success "Storage configuration applied"
    
    # Wait for PVCs to be bound
    log_info "Waiting for PVCs to be bound..."
    local timeout=120
    local count=0
    
    while true; do
        local primary_status=$(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        local standby_status=$(kubectl get pvc postgresql-standby-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        
        if [[ "$primary_status" == "Bound" && "$standby_status" == "Bound" ]]; then
            log_success "✓ All PVCs are bound"
            break
        fi
        
        if [[ $count -ge $timeout ]]; then
            log_error "Timeout waiting for PVCs to bind"
            log_info "Current PVC status:"
            kubectl get pvc -n "$NAMESPACE" | grep postgresql || true
            return 1
        fi
        
        echo -n "."
        sleep 2
        count=$((count + 2))
    done
}

# Function to deploy PostgreSQL
deploy_postgresql() {
    log_info "Deploying PostgreSQL with fixed storage..."
    
    # Deploy PostgreSQL primary
    kubectl apply -f "$SCRIPT_DIR/postgresql-primary.yaml"
    
    # Wait for primary to be ready
    log_info "Waiting for PostgreSQL primary to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgresql,component=primary -n "$NAMESPACE" --timeout=300s
    
    # Deploy PostgreSQL standby
    kubectl apply -f "$SCRIPT_DIR/postgresql-standby.yaml"
    
    # Wait for standby to be ready
    log_info "Waiting for PostgreSQL standby to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgresql,component=standby -n "$NAMESPACE" --timeout=300s
    
    log_success "PostgreSQL deployment completed successfully"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying PostgreSQL deployment..."
    
    # Check pod status
    log_info "PostgreSQL pods:"
    kubectl get pods -n "$NAMESPACE" -l app=postgresql
    
    # Check PVC status
    log_info "PostgreSQL PVCs:"
    kubectl get pvc -n "$NAMESPACE" | grep postgresql
    
    # Check services
    log_info "PostgreSQL services:"
    kubectl get svc -n "$NAMESPACE" -l app=postgresql
    
    # Test connectivity
    log_info "Testing PostgreSQL connectivity..."
    if kubectl exec -n "$NAMESPACE" deployment/postgresql-primary -- pg_isready -U postgres >/dev/null 2>&1; then
        log_success "✓ PostgreSQL primary is accessible"
    else
        log_warning "⚠ PostgreSQL primary connectivity test failed"
    fi
}

# Main function
main() {
    log_info "Starting PostgreSQL storage fix..."
    
    # Check if namespace exists
    if ! resource_exists namespace "$NAMESPACE"; then
        log_error "Namespace $NAMESPACE does not exist. Please create it first."
        exit 1
    fi
    
    # Check storage classes
    local storage_status=0
    check_storage_classes || storage_status=$?
    
    if [[ $storage_status -eq 2 ]]; then
        log_error "No suitable storage class found. Please install a storage provisioner."
        exit 1
    elif [[ $storage_status -eq 1 ]]; then
        log_warning "Using local-path storage. Consider NFS for production workloads."
        # Update storage class to use local-path
        sed -i.bak 's/postgresql-storage/postgresql-storage-local/g' "$SCRIPT_DIR/postgresql-storage.yaml"
        sed -i.bak 's/cluster.local\/nfs-subdir-external-provisioner/rancher.io\/local-path/g' "$SCRIPT_DIR/postgresql-storage.yaml"
    fi
    
    # Clean up existing resources
    cleanup_existing_resources
    
    # Deploy storage
    deploy_storage
    
    # Deploy PostgreSQL
    deploy_postgresql
    
    # Verify deployment
    verify_deployment
    
    log_success "🎉 PostgreSQL storage issue resolved successfully!"
    
    # Display next steps
    echo
    log_info "Next steps:"
    echo "1. Verify PostgreSQL is working: kubectl exec -n $NAMESPACE postgresql-primary-0 -- psql -U postgres -c '\\l'"
    echo "2. Check logs if needed: kubectl logs -n $NAMESPACE postgresql-primary-0"
    echo "3. Proceed with Airflow deployment"
    
    # Restore original storage configuration if modified
    if [[ -f "$SCRIPT_DIR/postgresql-storage.yaml.bak" ]]; then
        mv "$SCRIPT_DIR/postgresql-storage.yaml.bak" "$SCRIPT_DIR/postgresql-storage.yaml"
        log_info "Original storage configuration restored"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi