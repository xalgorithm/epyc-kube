#!/bin/bash

# Deploy Redis Sentinel Cluster for Airflow
# This script deploys a Redis Sentinel cluster with 3 replicas for high availability

set -euo pipefail

# Configuration
NAMESPACE="airflow"
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

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
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

# Function to create Redis storage configuration with detected storage class
create_redis_storage_config() {
    log_info "Creating Redis storage configuration..."
    
    local storage_config="$SCRIPT_DIR/redis-storage-dynamic.yaml"
    
    cat > "$storage_config" <<EOF
# Redis Storage Configuration - Auto-generated
# Uses detected storage class: $STORAGE_CLASS

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data-redis-0
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: storage
    storage-class: $STORAGE_CLASS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: $STORAGE_CLASS

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data-redis-1
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: storage
    storage-class: $STORAGE_CLASS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: $STORAGE_CLASS

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data-redis-2
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: storage
    storage-class: $STORAGE_CLASS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: $STORAGE_CLASS
EOF
    
    log_success "Redis storage configuration created: $storage_config"
    return 0
}

# Function to check for existing PVCs with different storage class
check_existing_pvcs() {
    log_info "Checking for existing Redis PVCs..."
    
    local existing_pvcs
    existing_pvcs=$(kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$existing_pvcs" ]]; then
        log_warning "Found existing Redis PVCs:"
        kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,STORAGE-CLASS:.spec.storageClassName"
        
        # Check if any PVC has a different storage class
        local conflicting_pvcs=()
        for pvc_name in $existing_pvcs; do
            local existing_sc
            existing_sc=$(kubectl get pvc "$pvc_name" -n "$NAMESPACE" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
            if [[ "$existing_sc" != "$STORAGE_CLASS" ]]; then
                conflicting_pvcs+=("$pvc_name")
            fi
        done
        
        if [[ ${#conflicting_pvcs[@]} -gt 0 ]]; then
            log_error "Storage class conflict detected!"
            log_error "Existing PVCs use different storage class than detected: $STORAGE_CLASS"
            log_error "Conflicting PVCs: ${conflicting_pvcs[*]}"
            echo ""
            log_info "To fix this issue, run one of these commands:"
            echo "  ./fix-redis-storage-auto.sh    # Automatic fix (deletes existing PVCs)"
            echo "  ./fix-redis-storage-class.sh   # Interactive fix with confirmation"
            echo ""
            log_error "Deployment stopped due to storage class conflict"
            exit 1
        else
            log_success "Existing PVCs use the correct storage class: $STORAGE_CLASS"
        fi
    else
        log_info "No existing Redis PVCs found"
    fi
}

# Function to wait for Redis PVCs to be bound
wait_for_redis_pvcs() {
    log_info "Waiting for Redis PVCs to be bound..."
    
    local pvcs=("redis-data-redis-0" "redis-data-redis-1" "redis-data-redis-2")
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
    
    log_success "All Redis PVCs are bound"
}

# Check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Creating namespace and RBAC: $NAMESPACE"
        kubectl apply -f "$SCRIPT_DIR/airflow-namespace-rbac.yaml"
    else
        log_info "Namespace $NAMESPACE already exists"
    fi
}

# Deploy Redis components
deploy_redis() {
    log_info "Deploying Redis Sentinel cluster..."
    
    # Detect storage class and create storage configuration
    detect_storage_class
    check_existing_pvcs
    create_redis_storage_config
    
    # Apply configurations in order
    local components=(
        "redis-secret.yaml"
        "redis-configmap.yaml"
        "redis-persistence-config.yaml"
        "redis-connection-pool.yaml"
        "redis-storage-dynamic.yaml"  # Use dynamic storage config
        "redis-headless-service.yaml"
        "redis-service.yaml"
    )
    
    for component in "${components[@]}"; do
        log_info "Applying $component..."
        if kubectl apply -f "$SCRIPT_DIR/$component"; then
            log_success "Applied $component"
        else
            log_error "Failed to apply $component"
            exit 1
        fi
        sleep 2
    done
    
    # Wait for PVCs to be bound before deploying StatefulSet
    wait_for_redis_pvcs
    
    # Deploy StatefulSet after storage is ready
    log_info "Deploying Redis StatefulSet..."
    
    # Create a temporary StatefulSet file with the correct storage class
    local temp_statefulset="$SCRIPT_DIR/redis-statefulset-temp.yaml"
    sed "s/STORAGE_CLASS_PLACEHOLDER/$STORAGE_CLASS/g" "$SCRIPT_DIR/redis-statefulset.yaml" > "$temp_statefulset"
    
    if kubectl apply -f "$temp_statefulset"; then
        log_success "Applied redis-statefulset.yaml"
        rm -f "$temp_statefulset"
    else
        log_error "Failed to apply redis-statefulset.yaml"
        rm -f "$temp_statefulset"
        exit 1
    fi
}

# Deploy monitoring components
deploy_monitoring() {
    log_info "Deploying Redis monitoring components..."
    
    local monitoring_components=(
        "redis-monitoring.yaml"
        "redis-servicemonitor.yaml"
    )
    
    for component in "${monitoring_components[@]}"; do
        log_info "Applying $component..."
        if kubectl apply -f "$SCRIPT_DIR/$component"; then
            log_success "Applied $component"
        else
            log_warning "Failed to apply $component (monitoring may not be available)"
        fi
        sleep 2
    done
}

# Wait for Redis pods to be ready
wait_for_redis() {
    log_info "Waiting for Redis pods to be ready..."
    
    # Wait for StatefulSet to be ready
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n "$NAMESPACE" --timeout=300s; then
        log_success "Redis pods are ready"
    else
        log_error "Timeout waiting for Redis pods to be ready"
        return 1
    fi
    
    # Wait a bit more for Sentinel to establish quorum
    log_info "Waiting for Sentinel quorum to be established..."
    sleep 30
}

# Test Redis cluster
test_redis_cluster() {
    log_info "Testing Redis cluster functionality..."
    
    # Get a Redis pod name
    local redis_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$redis_pod" ]]; then
        log_error "No Redis pods found"
        return 1
    fi
    
    log_info "Testing Redis connectivity using pod: $redis_pod"
    
    # Test Redis connection
    if kubectl exec -n "$NAMESPACE" "$redis_pod" -c redis -- redis-cli -a "airflow-redis-2024" --no-auth-warning ping; then
        log_success "Redis connection test passed"
    else
        log_error "Redis connection test failed"
        return 1
    fi
    
    # Test Sentinel connection
    if kubectl exec -n "$NAMESPACE" "$redis_pod" -c sentinel -- redis-cli -p 26379 -a "airflow-redis-2024" --no-auth-warning ping; then
        log_success "Sentinel connection test passed"
    else
        log_error "Sentinel connection test failed"
        return 1
    fi
    
    # Test master discovery
    local master_addr=$(kubectl exec -n "$NAMESPACE" "$redis_pod" -c sentinel -- redis-cli -p 26379 -a "airflow-redis-2024" --no-auth-warning sentinel get-master-addr-by-name mymaster 2>/dev/null || echo "")
    
    if [[ -n "$master_addr" ]]; then
        log_success "Master discovery test passed: $master_addr"
    else
        log_error "Master discovery test failed"
        return 1
    fi
    
    # Test basic Redis operations
    log_info "Testing basic Redis operations..."
    if kubectl exec -n "$NAMESPACE" "$redis_pod" -c redis -- redis-cli -a "airflow-redis-2024" --no-auth-warning set test_key "test_value" > /dev/null; then
        local retrieved_value=$(kubectl exec -n "$NAMESPACE" "$redis_pod" -c redis -- redis-cli -a "airflow-redis-2024" --no-auth-warning get test_key)
        if [[ "$retrieved_value" == "test_value" ]]; then
            log_success "Basic Redis operations test passed"
            kubectl exec -n "$NAMESPACE" "$redis_pod" -c redis -- redis-cli -a "airflow-redis-2024" --no-auth-warning del test_key > /dev/null
        else
            log_error "Basic Redis operations test failed: expected 'test_value', got '$retrieved_value'"
            return 1
        fi
    else
        log_error "Failed to set test key in Redis"
        return 1
    fi
}

# Show cluster status
show_cluster_status() {
    log_info "Redis Sentinel Cluster Status:"
    echo ""
    
    # Show pods
    log_info "Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o wide
    echo ""
    
    # Show services
    log_info "Services:"
    kubectl get services -n "$NAMESPACE" -l app.kubernetes.io/name=redis
    echo ""
    
    # Show persistent volumes
    log_info "Persistent Volume Claims:"
    kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis
    echo ""
    
    # Show StatefulSet
    log_info "StatefulSet:"
    kubectl get statefulset -n "$NAMESPACE" redis
    echo ""
    
    # Show storage class information
    if [[ -n "$STORAGE_CLASS" ]]; then
        log_info "Storage Configuration:"
        echo "  Storage Class: $STORAGE_CLASS"
        echo "  Storage Size: 10Gi per Redis instance"
        echo "  Total Storage: 30Gi (3 instances)"
        echo ""
    fi
}

# Show connection information
show_connection_info() {
    log_info "Redis Connection Information:"
    echo ""
    echo "Redis Service: redis.airflow.svc.cluster.local:6379"
    echo "Sentinel Service: redis-sentinel.airflow.svc.cluster.local:26379"
    echo "Headless Service: redis-headless.airflow.svc.cluster.local"
    echo ""
    echo "Individual Sentinel Endpoints:"
    echo "  - redis-0.redis-headless.airflow.svc.cluster.local:26379"
    echo "  - redis-1.redis-headless.airflow.svc.cluster.local:26379"
    echo "  - redis-2.redis-headless.airflow.svc.cluster.local:26379"
    echo ""
    echo "Password: stored in secret 'redis-secret' (key: redis-password)"
    echo "Service Name: mymaster"
    echo ""
    echo "Celery Broker URL:"
    echo "sentinel://:password@redis-0.redis-headless.airflow.svc.cluster.local:26379;redis-1.redis-headless.airflow.svc.cluster.local:26379;redis-2.redis-headless.airflow.svc.cluster.local:26379/0?sentinel_service_name=mymaster"
    echo ""
    log_info "Troubleshooting Commands:"
    echo "- Check storage status: $SCRIPT_DIR/check-airflow-storage.sh"
    echo "- Check Redis pods: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=redis"
    echo "- Check Redis PVCs: kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=redis"
    echo "- Check storage class: kubectl describe storageclass ${STORAGE_CLASS:-auto-detected}"
    echo "- Test Redis: $0 test"
    echo "- View logs: kubectl logs -n $NAMESPACE redis-0 -c redis"
}

# Cleanup function
cleanup_redis() {
    log_warning "Cleaning up Redis deployment..."
    
    local components=(
        "redis-servicemonitor.yaml"
        "redis-monitoring.yaml"
        "redis-statefulset.yaml"
        "redis-service.yaml"
        "redis-headless-service.yaml"
        "redis-storage-dynamic.yaml"
        "redis-storage.yaml"  # Also clean up old static config
        "redis-connection-pool.yaml"
        "redis-persistence-config.yaml"
        "redis-configmap.yaml"
        "redis-secret.yaml"
    )
    
    for component in "${components[@]}"; do
        log_info "Deleting $component..."
        kubectl delete -f "$SCRIPT_DIR/$component" --ignore-not-found=true
    done
    
    # Delete PVCs
    log_info "Deleting persistent volume claims..."
    kubectl delete pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis --ignore-not-found=true
    
    # Clean up generated files
    if [[ -f "$SCRIPT_DIR/redis-storage-dynamic.yaml" ]]; then
        log_info "Removing generated storage configuration..."
        rm -f "$SCRIPT_DIR/redis-storage-dynamic.yaml"
    fi
    
    log_success "Redis cleanup completed"
}

# Main function
main() {
    log_info "Starting Redis Sentinel cluster deployment..."
    
    check_kubectl
    check_namespace
    
    case "${1:-deploy}" in
        "deploy")
            deploy_redis
            deploy_monitoring
            wait_for_redis
            test_redis_cluster
            show_cluster_status
            show_connection_info
            log_success "Redis Sentinel cluster deployment completed successfully!"
            ;;
        "test")
            test_redis_cluster
            ;;
        "status")
            show_cluster_status
            show_connection_info
            ;;
        "cleanup"|"clean")
            cleanup_redis
            ;;
        "monitoring")
            deploy_monitoring
            ;;
        *)
            echo "Usage: $0 {deploy|test|status|cleanup|monitoring}"
            echo ""
            echo "Commands:"
            echo "  deploy     - Deploy Redis Sentinel cluster (default)"
            echo "  test       - Test cluster functionality"
            echo "  status     - Show cluster status"
            echo "  cleanup    - Remove Redis deployment"
            echo "  monitoring - Deploy monitoring components only"
            exit 1
            ;;
    esac
}

# Handle command line arguments
main "$@"