#!/bin/bash
set -euo pipefail

# PostgreSQL High Availability Deployment Script
# This script deploys PostgreSQL with primary-standby replication for Airflow

echo "=== Deploying PostgreSQL High Availability Setup ==="

# Configuration
NAMESPACE="airflow"
KUBECTL_TIMEOUT="300s"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORAGE_CLASS=""  # Will be detected automatically

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

# Function to detect and set storage class
detect_storage_class() {
    log_info "Detecting available storage classes..."
    
    if kubectl get storageclass nfs-client >/dev/null 2>&1; then
        STORAGE_CLASS="nfs-client"
        log_success "✓ Using NFS storage class: $STORAGE_CLASS (recommended)"
    elif kubectl get storageclass local-path >/dev/null 2>&1; then
        STORAGE_CLASS="local-path"
        log_warning "⚠ Using local-path storage class: $STORAGE_CLASS (development only)"
    else
        # Try to find any NFS-based storage class
        local nfs_classes
        nfs_classes=$(kubectl get storageclass -o jsonpath='{.items[?(@.provisioner=="cluster.local/nfs-subdir-external-provisioner")].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$nfs_classes" ]]; then
            STORAGE_CLASS=$(echo "$nfs_classes" | head -n1)
            log_success "✓ Using NFS storage class: $STORAGE_CLASS"
        else
            # Use default storage class as fallback
            local default_sc
            default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
            
            if [[ -n "$default_sc" ]]; then
                STORAGE_CLASS="$default_sc"
                log_warning "⚠ Using default storage class: $STORAGE_CLASS"
            else
                log_error "✗ No suitable storage class found"
                log_error "Please install a storage provisioner (NFS recommended)"
                exit 1
            fi
        fi
    fi
    
    log_info "Selected storage class: $STORAGE_CLASS"
}

# Function to create storage configuration with detected storage class
create_storage_config() {
    log_info "Creating PostgreSQL storage configuration..."
    
    local storage_config="$SCRIPT_DIR/postgresql-storage-dynamic.yaml"
    
    cat > "$storage_config" <<EOF
# PostgreSQL Storage Configuration - Auto-generated
# Uses detected storage class: $STORAGE_CLASS

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-primary-pvc
  namespace: $NAMESPACE
  labels:
    app: postgresql
    component: primary
    storage-class: $STORAGE_CLASS
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $STORAGE_CLASS
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
    storage-class: $STORAGE_CLASS
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: 100Gi
EOF
    
    log_success "Storage configuration created: $storage_config"
    return 0
}

# Function to wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300s}
    
    log_info "Waiting for $resource_type/$resource_name to be ready..."
    kubectl wait --for=condition=ready "$resource_type/$resource_name" -n "$namespace" --timeout="$timeout" || {
        log_error "Timeout waiting for $resource_type/$resource_name"
        return 1
    }
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
}

# Function to wait for PVCs to be bound
wait_for_pvcs() {
    log_info "Waiting for PostgreSQL PVCs to be bound..."
    
    local pvcs=("postgresql-primary-pvc" "postgresql-standby-pvc")
    local timeout=120
    local count=0
    
    for pvc in "${pvcs[@]}"; do
        log_info "Waiting for $pvc to be bound..."
        
        while true; do
            local status
            status=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
            
            if [[ "$status" == "Bound" ]]; then
                log_success "✓ $pvc is bound"
                break
            elif [[ "$status" == "Pending" ]]; then
                if [[ $count -ge $timeout ]]; then
                    log_error "Timeout waiting for $pvc to bind"
                    log_error "Check storage class and provisioner: $STORAGE_CLASS"
                    return 1
                fi
                echo -n "."
                sleep 2
                count=$((count + 2))
            else
                log_error "PVC $pvc has unexpected status: $status"
                return 1
            fi
        done
    done
    
    log_success "All PostgreSQL PVCs are bound"
}

log_info "Step 1: Detecting storage class and creating configuration..."
detect_storage_class
create_storage_config

log_info "Step 2: Creating namespace and RBAC..."
kubectl apply -f "$SCRIPT_DIR/airflow-namespace-rbac.yaml"

log_info "Step 3: Creating storage resources..."
kubectl apply -f "$SCRIPT_DIR/postgresql-storage-dynamic.yaml"

# Wait for PVCs to be bound
wait_for_pvcs

log_info "Step 4: Creating secrets and configuration..."
kubectl apply -f "$SCRIPT_DIR/postgresql-secret.yaml"

# Validate PostgreSQL init scripts before applying
log_info "Validating PostgreSQL initialization scripts..."
if ! "$SCRIPT_DIR/verify-postgresql-init-scripts.sh" >/dev/null 2>&1; then
    log_warning "PostgreSQL init scripts have syntax issues, applying fixes..."
    kubectl apply -f "$SCRIPT_DIR/postgresql-configmap.yaml"
    log_success "PostgreSQL configuration applied with fixes"
else
    kubectl apply -f "$SCRIPT_DIR/postgresql-configmap.yaml"
    log_success "PostgreSQL configuration validated and applied"
fi

log_info "Step 5: Deploying PostgreSQL primary..."
kubectl apply -f "$SCRIPT_DIR/postgresql-primary.yaml"

# Wait for primary to be ready
log_info "Waiting for PostgreSQL primary to be ready..."
wait_for_resource "statefulset" "postgresql-primary" "$NAMESPACE" "$KUBECTL_TIMEOUT"

# Wait for primary pod to be running
kubectl wait --for=condition=ready pod/postgresql-primary-0 -n "$NAMESPACE" --timeout="$KUBECTL_TIMEOUT"

log_info "Step 6: Verifying primary database..."
# Test primary connectivity
kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- pg_isready -U postgres

log_info "Step 7: Deploying PostgreSQL standby..."
kubectl apply -f "$SCRIPT_DIR/postgresql-standby.yaml"

# Wait for standby to be ready
log_info "Waiting for PostgreSQL standby to be ready..."
wait_for_resource "statefulset" "postgresql-standby" "$NAMESPACE" "$KUBECTL_TIMEOUT"

# Wait for standby pod to be running
kubectl wait --for=condition=ready pod/postgresql-standby-0 -n "$NAMESPACE" --timeout="$KUBECTL_TIMEOUT"

log_info "Step 8: Setting up backup system..."
kubectl apply -f "$SCRIPT_DIR/postgresql-backup.yaml"

log_info "Step 9: Setting up monitoring and health checks..."
kubectl apply -f "$SCRIPT_DIR/postgresql-monitoring.yaml"

log_info "Step 10: Verifying replication setup..."
sleep 10  # Give replication time to establish

# Check replication status
log_info "Checking replication status..."
kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Verify standby is in recovery mode
STANDBY_RECOVERY=$(kubectl exec -n "$NAMESPACE" postgresql-standby-0 -- psql -U postgres -t -c "SELECT pg_is_in_recovery();" | tr -d ' ')
if [ "$STANDBY_RECOVERY" = "t" ]; then
    log_success "✓ Standby is correctly in recovery mode"
else
    log_warning "⚠ Warning: Standby is not in recovery mode"
fi

echo ""
log_success "=== PostgreSQL High Availability Deployment Complete ==="
echo ""
log_info "Deployment Summary:"
echo "- Namespace: $NAMESPACE"
echo "- Storage Class: $STORAGE_CLASS"
echo "- Primary: postgresql-primary-0"
echo "- Standby: postgresql-standby-0"
echo "- Storage Size: 100Gi per instance"
echo "- Backup schedule: Daily at 2 AM UTC"
echo "- Health checks: Every 5 minutes"
echo ""
log_info "Connection Information:"
echo "- Primary endpoint: postgresql-primary.$NAMESPACE.svc.cluster.local:5432"
echo "- Standby endpoint: postgresql-standby.$NAMESPACE.svc.cluster.local:5432"
echo "- Database: airflow"
echo "- Username: airflow (from secret)"
echo ""
log_info "Storage Information:"
kubectl get pvc -n "$NAMESPACE" | grep postgresql | sed 's/^/  /'
echo ""
log_info "Useful Commands:"
echo "- Check status: kubectl get pods -n $NAMESPACE"
echo "- Check storage: kubectl get pvc -n $NAMESPACE"
echo "- View logs: kubectl logs -n $NAMESPACE postgresql-primary-0"
echo "- Connect to primary: kubectl exec -it -n $NAMESPACE postgresql-primary-0 -- psql -U airflow -d airflow"
echo "- Run health check: kubectl create job --from=cronjob/postgresql-health-check manual-health-check -n $NAMESPACE"
echo "- Test connection: kubectl exec -n $NAMESPACE postgresql-primary-0 -- /scripts/connection-test.sh postgresql-primary"
echo "- Check replication: kubectl exec -n $NAMESPACE postgresql-primary-0 -- /scripts/replication-status.sh"
echo ""
log_info "Troubleshooting:"
echo "- Check storage status: $SCRIPT_DIR/check-airflow-storage.sh postgresql"
echo "- Fix storage issues: $SCRIPT_DIR/fix-postgresql-storage.sh"
echo "- Check storage class: kubectl describe storageclass $STORAGE_CLASS"
echo ""
log_info "Next Steps:"
echo "1. Update secrets with actual secure passwords"
echo "2. Configure external backup storage (S3, etc.)"
echo "3. Set up monitoring alerts"
echo "4. Test failover procedures"
echo ""