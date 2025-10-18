#!/bin/bash

# Test Storage Class Detection
# This script tests the storage class detection logic used in deployment scripts

set -euo pipefail

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

# Function to detect storage class (same logic as deployment scripts)
detect_storage_class() {
    local STORAGE_CLASS=""
    local VERBOSE="${1:-true}"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Detecting available storage classes..."
    fi
    
    if kubectl get storageclass nfs-client >/dev/null 2>&1; then
        STORAGE_CLASS="nfs-client"
        if [[ "$VERBOSE" == "true" ]]; then
            log_success "✓ Using NFS storage class: $STORAGE_CLASS (recommended)"
        fi
    elif kubectl get storageclass local-path >/dev/null 2>&1; then
        STORAGE_CLASS="local-path"
        if [[ "$VERBOSE" == "true" ]]; then
            log_warning "⚠ Using local-path storage class: $STORAGE_CLASS (development only)"
        fi
    else
        # Try to find any NFS-based storage class
        local nfs_classes
        nfs_classes=$(kubectl get storageclass -o jsonpath='{.items[?(@.provisioner=="cluster.local/nfs-subdir-external-provisioner")].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$nfs_classes" ]]; then
            STORAGE_CLASS=$(echo "$nfs_classes" | head -n1)
            if [[ "$VERBOSE" == "true" ]]; then
                log_success "✓ Using NFS storage class: $STORAGE_CLASS"
            fi
        else
            # Use default storage class as fallback
            local default_sc
            default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
            
            if [[ -n "$default_sc" ]]; then
                STORAGE_CLASS="$default_sc"
                if [[ "$VERBOSE" == "true" ]]; then
                    log_warning "⚠ Using default storage class: $STORAGE_CLASS"
                fi
            else
                if [[ "$VERBOSE" == "true" ]]; then
                    log_error "✗ No suitable storage class found"
                fi
                return 1
            fi
        fi
    fi
    
    echo "$STORAGE_CLASS"
}

# Function to test PostgreSQL storage detection
test_postgresql_detection() {
    log_info "Testing PostgreSQL storage class detection..."
    
    local storage_class
    if storage_class=$(detect_storage_class false); then
        log_success "PostgreSQL would use storage class: $storage_class"
        
        # Test if we can create a sample PVC configuration
        local test_config="/tmp/test-postgresql-storage.yaml"
        cat > "$test_config" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-postgresql-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $storage_class
  resources:
    requests:
      storage: 1Gi
EOF
        
        if kubectl apply --dry-run=client -f "$test_config" >/dev/null 2>&1; then
            log_success "✓ PostgreSQL storage configuration is valid"
        else
            log_error "✗ PostgreSQL storage configuration is invalid"
            return 1
        fi
        
        rm -f "$test_config"
    else
        log_error "✗ PostgreSQL storage class detection failed"
        return 1
    fi
}

# Function to test Redis storage detection
test_redis_detection() {
    log_info "Testing Redis storage class detection..."
    
    local storage_class
    if storage_class=$(detect_storage_class false); then
        log_success "Redis would use storage class: $storage_class"
        
        # Test if we can create a sample PVC configuration
        local test_config="/tmp/test-redis-storage.yaml"
        cat > "$test_config" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-redis-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $storage_class
  resources:
    requests:
      storage: 1Gi
EOF
        
        if kubectl apply --dry-run=client -f "$test_config" >/dev/null 2>&1; then
            log_success "✓ Redis storage configuration is valid"
        else
            log_error "✗ Redis storage configuration is invalid"
            return 1
        fi
        
        rm -f "$test_config"
    else
        log_error "✗ Redis storage class detection failed"
        return 1
    fi
}

# Function to show storage class details
show_storage_details() {
    log_info "Available Storage Classes:"
    echo "=========================="
    
    if kubectl get storageclass >/dev/null 2>&1; then
        kubectl get storageclass -o custom-columns="NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class"
        echo ""
        
        # Show details for detected storage class
        local storage_class
        if storage_class=$(detect_storage_class false 2>/dev/null); then
            log_info "Details for selected storage class: $storage_class"
            kubectl describe storageclass "$storage_class" | head -20
        fi
    else
        log_error "No storage classes found"
        return 1
    fi
}

# Function to test actual deployment scripts
test_deployment_scripts() {
    log_info "Testing deployment script storage detection..."
    
    # Test PostgreSQL script
    if [[ -f "deploy-postgresql.sh" ]]; then
        log_info "Testing PostgreSQL deployment script..."
        if bash -n deploy-postgresql.sh; then
            log_success "✓ PostgreSQL script syntax is valid"
        else
            log_error "✗ PostgreSQL script has syntax errors"
            return 1
        fi
    else
        log_warning "⚠ PostgreSQL deployment script not found"
    fi
    
    # Test Redis script
    if [[ -f "deploy-redis.sh" ]]; then
        log_info "Testing Redis deployment script..."
        if bash -n deploy-redis.sh; then
            log_success "✓ Redis script syntax is valid"
        else
            log_error "✗ Redis script has syntax errors"
            return 1
        fi
    else
        log_warning "⚠ Redis deployment script not found"
    fi
}

# Function to run comprehensive test
run_comprehensive_test() {
    log_info "Running comprehensive storage detection test..."
    echo "=============================================="
    echo ""
    
    local test_results=()
    
    # Test storage class detection
    if detect_storage_class false >/dev/null 2>&1; then
        test_results+=("✅ Storage class detection")
    else
        test_results+=("❌ Storage class detection")
    fi
    
    # Test PostgreSQL detection
    if test_postgresql_detection; then
        test_results+=("✅ PostgreSQL storage")
    else
        test_results+=("❌ PostgreSQL storage")
    fi
    
    # Test Redis detection
    if test_redis_detection; then
        test_results+=("✅ Redis storage")
    else
        test_results+=("❌ Redis storage")
    fi
    
    # Test deployment scripts
    if test_deployment_scripts; then
        test_results+=("✅ Deployment scripts")
    else
        test_results+=("❌ Deployment scripts")
    fi
    
    echo ""
    show_storage_details
    
    echo ""
    log_info "Test Results Summary:"
    echo "===================="
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    
    # Check if any tests failed
    if printf '%s\n' "${test_results[@]}" | grep -q "❌"; then
        echo ""
        log_warning "⚠️  Some tests failed - please review storage configuration"
        return 1
    else
        echo ""
        log_success "🎉 All storage detection tests passed!"
        return 0
    fi
}

# Main execution
main() {
    case "${1:-test}" in
        "test")
            run_comprehensive_test
            ;;
        "detect")
            detect_storage_class
            ;;
        "postgresql"|"postgres")
            test_postgresql_detection
            ;;
        "redis")
            test_redis_detection
            ;;
        "details")
            show_storage_details
            ;;
        "scripts")
            test_deployment_scripts
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  test        - Run comprehensive storage detection test (default)"
            echo "  detect      - Show detected storage class"
            echo "  postgresql  - Test PostgreSQL storage detection"
            echo "  redis       - Test Redis storage detection"
            echo "  details     - Show storage class details"
            echo "  scripts     - Test deployment script syntax"
            echo "  help        - Show this help message"
            echo ""
            echo "This script tests the storage class detection logic"
            echo "used in the PostgreSQL and Redis deployment scripts."
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"