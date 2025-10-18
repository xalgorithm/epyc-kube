#!/bin/bash

# Verify PostgreSQL Deployment Readiness
# This script verifies that the environment is ready for PostgreSQL deployment

set -euo pipefail

# Configuration
NAMESPACE="airflow"

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

# Function to check namespace and RBAC
check_namespace_rbac() {
    log_info "Checking namespace and RBAC configuration..."
    
    # Check namespace exists
    if resource_exists namespace "$NAMESPACE"; then
        log_success "✓ Namespace '$NAMESPACE' exists"
    else
        log_error "✗ Namespace '$NAMESPACE' not found"
        return 1
    fi
    
    # Check service accounts
    local service_accounts=("airflow-webserver" "airflow-scheduler" "airflow-worker" "airflow-triggerer")
    local missing_sa=()
    
    for sa in "${service_accounts[@]}"; do
        if resource_exists serviceaccount "$sa" "$NAMESPACE"; then
            log_success "✓ ServiceAccount '$sa' exists"
        else
            log_warning "⚠ ServiceAccount '$sa' not found"
            missing_sa+=("$sa")
        fi
    done
    
    if [[ ${#missing_sa[@]} -gt 0 ]]; then
        log_warning "Missing service accounts: ${missing_sa[*]}"
        log_info "Run './deploy-airflow-rbac.sh' to create missing RBAC resources"
    fi
    
    return 0
}

# Function to check storage class availability
check_storage_class() {
    log_info "Checking storage class availability..."
    
    if kubectl get storageclass nfs-client >/dev/null 2>&1; then
        log_success "✓ NFS storage class (nfs-client) is available"
        
        # Show storage class details
        local provisioner
        provisioner=$(kubectl get storageclass nfs-client -o jsonpath='{.provisioner}')
        local reclaim_policy
        reclaim_policy=$(kubectl get storageclass nfs-client -o jsonpath='{.reclaimPolicy}')
        local binding_mode
        binding_mode=$(kubectl get storageclass nfs-client -o jsonpath='{.volumeBindingMode}')
        
        echo "    Provisioner: $provisioner"
        echo "    Reclaim Policy: $reclaim_policy"
        echo "    Binding Mode: $binding_mode"
        
        return 0
    elif kubectl get storageclass local-path >/dev/null 2>&1; then
        log_warning "⚠ Only local-path storage class available (development use)"
        return 0
    else
        log_error "✗ No suitable storage class found"
        log_error "Please install a storage provisioner before deploying PostgreSQL"
        return 1
    fi
}

# Function to verify no existing PostgreSQL components
check_no_postgresql_components() {
    log_info "Verifying no existing PostgreSQL components..."
    
    local components_found=false
    
    # Check pods
    if kubectl get pods -n "$NAMESPACE" | grep -q postgresql; then
        log_warning "⚠ PostgreSQL pods found:"
        kubectl get pods -n "$NAMESPACE" | grep postgresql | sed 's/^/    /'
        components_found=true
    else
        log_success "✓ No PostgreSQL pods found"
    fi
    
    # Check StatefulSets
    if kubectl get statefulsets -n "$NAMESPACE" | grep -q postgresql; then
        log_warning "⚠ PostgreSQL StatefulSets found:"
        kubectl get statefulsets -n "$NAMESPACE" | grep postgresql | sed 's/^/    /'
        components_found=true
    else
        log_success "✓ No PostgreSQL StatefulSets found"
    fi
    
    # Check Services
    if kubectl get services -n "$NAMESPACE" | grep -q postgresql; then
        log_warning "⚠ PostgreSQL Services found:"
        kubectl get services -n "$NAMESPACE" | grep postgresql | sed 's/^/    /'
        components_found=true
    else
        log_success "✓ No PostgreSQL Services found"
    fi
    
    # Check PVCs
    if kubectl get pvc -n "$NAMESPACE" | grep -q postgresql; then
        log_warning "⚠ PostgreSQL PVCs found:"
        kubectl get pvc -n "$NAMESPACE" | grep postgresql | sed 's/^/    /'
        components_found=true
    else
        log_success "✓ No PostgreSQL PVCs found"
    fi
    
    # Check Secrets
    if kubectl get secrets -n "$NAMESPACE" | grep -q postgresql; then
        log_warning "⚠ PostgreSQL Secrets found:"
        kubectl get secrets -n "$NAMESPACE" | grep postgresql | sed 's/^/    /'
        components_found=true
    else
        log_success "✓ No PostgreSQL Secrets found"
    fi
    
    # Check ConfigMaps
    if kubectl get configmaps -n "$NAMESPACE" | grep -q postgresql; then
        log_warning "⚠ PostgreSQL ConfigMaps found:"
        kubectl get configmaps -n "$NAMESPACE" | grep postgresql | sed 's/^/    /'
        components_found=true
    else
        log_success "✓ No PostgreSQL ConfigMaps found"
    fi
    
    if [[ "$components_found" == "true" ]]; then
        log_warning "Existing PostgreSQL components found"
        log_info "Run './cleanup-postgresql.sh cleanup' to remove them"
        return 1
    else
        log_success "✓ Environment is clean - no existing PostgreSQL components"
        return 0
    fi
}

# Function to check deployment script readiness
check_deployment_script() {
    log_info "Checking PostgreSQL deployment script..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local deploy_script="$script_dir/deploy-postgresql.sh"
    
    if [[ -f "$deploy_script" ]]; then
        log_success "✓ PostgreSQL deployment script found"
        
        # Check script syntax
        if bash -n "$deploy_script"; then
            log_success "✓ Deployment script syntax is valid"
        else
            log_error "✗ Deployment script has syntax errors"
            return 1
        fi
        
        # Check if script is executable
        if [[ -x "$deploy_script" ]]; then
            log_success "✓ Deployment script is executable"
        else
            log_warning "⚠ Deployment script is not executable"
            log_info "Run: chmod +x $deploy_script"
        fi
        
        return 0
    else
        log_error "✗ PostgreSQL deployment script not found: $deploy_script"
        return 1
    fi
}

# Function to check required configuration files
check_required_files() {
    log_info "Checking required PostgreSQL configuration files..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local required_files=(
        "postgresql-primary.yaml"
        "postgresql-standby.yaml"
        "postgresql-secret.yaml"
        "postgresql-configmap.yaml"
        "postgresql-backup.yaml"
        "postgresql-monitoring.yaml"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ -f "$script_dir/$file" ]]; then
            log_success "✓ $file found"
        else
            log_warning "⚠ $file not found"
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_warning "Missing configuration files: ${missing_files[*]}"
        log_info "Some PostgreSQL features may not be available"
        return 1
    else
        log_success "✓ All required configuration files found"
        return 0
    fi
}

# Function to test storage detection
test_storage_detection() {
    log_info "Testing storage class detection..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local test_script="$script_dir/test-storage-detection.sh"
    
    if [[ -f "$test_script" ]]; then
        local storage_class
        if storage_class=$("$test_script" detect 2>/dev/null | tail -n1); then
            log_success "✓ Storage class detection works: $storage_class"
            return 0
        else
            log_error "✗ Storage class detection failed"
            return 1
        fi
    else
        log_warning "⚠ Storage detection test script not found"
        return 1
    fi
}

# Function to run comprehensive readiness check
run_readiness_check() {
    log_info "PostgreSQL Deployment Readiness Check"
    echo "======================================"
    echo ""
    
    local check_results=()
    
    # Run all checks
    if check_namespace_rbac; then
        check_results+=("✅ Namespace and RBAC")
    else
        check_results+=("❌ Namespace and RBAC")
    fi
    
    if check_storage_class; then
        check_results+=("✅ Storage class")
    else
        check_results+=("❌ Storage class")
    fi
    
    if check_no_postgresql_components; then
        check_results+=("✅ Clean environment")
    else
        check_results+=("❌ Clean environment")
    fi
    
    if check_deployment_script; then
        check_results+=("✅ Deployment script")
    else
        check_results+=("❌ Deployment script")
    fi
    
    if check_required_files; then
        check_results+=("✅ Configuration files")
    else
        check_results+=("⚠️ Configuration files")
    fi
    
    if test_storage_detection; then
        check_results+=("✅ Storage detection")
    else
        check_results+=("❌ Storage detection")
    fi
    
    echo ""
    log_info "Readiness Check Results:"
    echo "======================="
    for result in "${check_results[@]}"; do
        echo "$result"
    done
    
    # Determine overall readiness
    if printf '%s\n' "${check_results[@]}" | grep -q "❌"; then
        echo ""
        log_error "❌ Environment is NOT ready for PostgreSQL deployment"
        log_info "Please address the issues above before running deploy-postgresql.sh"
        return 1
    elif printf '%s\n' "${check_results[@]}" | grep -q "⚠️"; then
        echo ""
        log_warning "⚠️ Environment is mostly ready with some warnings"
        log_info "You can proceed with deployment, but some features may be limited"
        return 0
    else
        echo ""
        log_success "🎉 Environment is ready for PostgreSQL deployment!"
        echo ""
        log_info "Next steps:"
        echo "1. Run: ./deploy-postgresql.sh"
        echo "2. Monitor: kubectl get pods -n $NAMESPACE -w"
        echo "3. Verify: ./check-airflow-storage.sh postgresql"
        return 0
    fi
}

# Main execution
main() {
    case "${1:-check}" in
        "check")
            run_readiness_check
            ;;
        "namespace")
            check_namespace_rbac
            ;;
        "storage")
            check_storage_class
            ;;
        "clean")
            check_no_postgresql_components
            ;;
        "script")
            check_deployment_script
            ;;
        "files")
            check_required_files
            ;;
        "detection")
            test_storage_detection
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  check      - Run comprehensive readiness check (default)"
            echo "  namespace  - Check namespace and RBAC only"
            echo "  storage    - Check storage class only"
            echo "  clean      - Check for existing PostgreSQL components"
            echo "  script     - Check deployment script only"
            echo "  files      - Check required configuration files"
            echo "  detection  - Test storage class detection"
            echo "  help       - Show this help message"
            echo ""
            echo "This script verifies that the environment is ready"
            echo "for PostgreSQL deployment using deploy-postgresql.sh"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"