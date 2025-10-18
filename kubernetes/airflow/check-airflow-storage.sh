#!/bin/bash

# Check Airflow Storage Configuration
# This script provides a comprehensive overview of storage configuration and status

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

# Function to get resource status
get_pvc_status() {
    local pvc_name="$1"
    local namespace="$2"
    
    if resource_exists pvc "$pvc_name" "$namespace"; then
        kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.status.phase}'
    else
        echo "NotFound"
    fi
}

# Function to get storage class
get_pvc_storage_class() {
    local pvc_name="$1"
    local namespace="$2"
    
    if resource_exists pvc "$pvc_name" "$namespace"; then
        kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.storageClassName}'
    else
        echo "N/A"
    fi
}

# Function to get storage size
get_pvc_size() {
    local pvc_name="$1"
    local namespace="$2"
    
    if resource_exists pvc "$pvc_name" "$namespace"; then
        kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.resources.requests.storage}'
    else
        echo "N/A"
    fi
}

# Function to check storage classes
check_storage_classes() {
    log_info "Available Storage Classes:"
    echo "=========================="
    
    if kubectl get storageclass >/dev/null 2>&1; then
        kubectl get storageclass -o custom-columns="NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,BINDING:.volumeBindingMode"
        echo
        
        # Check for recommended storage classes
        if kubectl get storageclass nfs-client >/dev/null 2>&1; then
            log_success "✓ NFS storage class (nfs-client) is available - RECOMMENDED"
        else
            log_warning "⚠ NFS storage class (nfs-client) not found"
        fi
        
        if kubectl get storageclass local-path >/dev/null 2>&1; then
            log_info "✓ Local path storage class available - OK for development"
        fi
        
        # Check default storage class
        local default_sc
        default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$default_sc" ]]; then
            log_info "Default storage class: $default_sc"
        else
            log_warning "No default storage class configured"
        fi
    else
        log_error "No storage classes found"
    fi
}

# Function to check PostgreSQL storage
check_postgresql_storage() {
    log_info "PostgreSQL Storage Status:"
    echo "=========================="
    
    local postgres_pvcs=("postgresql-primary-pvc" "postgresql-standby-pvc")
    local all_good=true
    
    for pvc in "${postgres_pvcs[@]}"; do
        local status
        local storage_class
        local size
        
        status=$(get_pvc_status "$pvc" "$NAMESPACE")
        storage_class=$(get_pvc_storage_class "$pvc" "$NAMESPACE")
        size=$(get_pvc_size "$pvc" "$NAMESPACE")
        
        echo "  $pvc:"
        echo "    Status: $status"
        echo "    Storage Class: $storage_class"
        echo "    Size: $size"
        
        if [[ "$status" == "Bound" ]]; then
            log_success "    ✓ PVC is bound and ready"
        elif [[ "$status" == "Pending" ]]; then
            log_warning "    ⚠ PVC is pending - check storage class and provisioner"
            all_good=false
        elif [[ "$status" == "NotFound" ]]; then
            log_error "    ✗ PVC not found"
            all_good=false
        else
            log_warning "    ⚠ PVC status: $status"
            all_good=false
        fi
        echo
    done
    
    # Check PostgreSQL pods
    log_info "PostgreSQL Pod Status:"
    if kubectl get pods -n "$NAMESPACE" -l app=postgresql >/dev/null 2>&1; then
        kubectl get pods -n "$NAMESPACE" -l app=postgresql -o wide
    else
        log_warning "No PostgreSQL pods found"
        all_good=false
    fi
    
    echo
    return $([ "$all_good" = true ] && echo 0 || echo 1)
}

# Function to check Airflow storage
check_airflow_storage() {
    log_info "Airflow Storage Status:"
    echo "======================="
    
    local airflow_pvcs=("airflow-dags-pvc" "airflow-logs-pvc" "airflow-config-pvc")
    local required_pvcs=("airflow-dags-pvc" "airflow-logs-pvc")
    local all_good=true
    
    for pvc in "${airflow_pvcs[@]}"; do
        local status
        local storage_class
        local size
        
        status=$(get_pvc_status "$pvc" "$NAMESPACE")
        storage_class=$(get_pvc_storage_class "$pvc" "$NAMESPACE")
        size=$(get_pvc_size "$pvc" "$NAMESPACE")
        
        echo "  $pvc:"
        echo "    Status: $status"
        echo "    Storage Class: $storage_class"
        echo "    Size: $size"
        
        if [[ "$status" == "Bound" ]]; then
            log_success "    ✓ PVC is bound and ready"
        elif [[ "$status" == "Pending" ]]; then
            log_warning "    ⚠ PVC is pending - check storage class and provisioner"
            if [[ " ${required_pvcs[*]} " =~ " $pvc " ]]; then
                all_good=false
            fi
        elif [[ "$status" == "NotFound" ]]; then
            if [[ " ${required_pvcs[*]} " =~ " $pvc " ]]; then
                log_error "    ✗ Required PVC not found"
                all_good=false
            else
                log_info "    ℹ Optional PVC not found"
            fi
        else
            log_warning "    ⚠ PVC status: $status"
            if [[ " ${required_pvcs[*]} " =~ " $pvc " ]]; then
                all_good=false
            fi
        fi
        echo
    done
    
    return $([ "$all_good" = true ] && echo 0 || echo 1)
}

# Function to check storage consistency
check_storage_consistency() {
    log_info "Storage Consistency Check:"
    echo "=========================="
    
    local storage_classes=()
    local pvcs=("postgresql-primary-pvc" "postgresql-standby-pvc" "airflow-dags-pvc" "airflow-logs-pvc")
    
    # Collect storage classes from existing PVCs
    for pvc in "${pvcs[@]}"; do
        if resource_exists pvc "$pvc" "$NAMESPACE"; then
            local sc
            sc=$(get_pvc_storage_class "$pvc" "$NAMESPACE")
            if [[ "$sc" != "N/A" && "$sc" != "" ]]; then
                storage_classes+=("$sc")
            fi
        fi
    done
    
    # Check for consistency
    if [[ ${#storage_classes[@]} -eq 0 ]]; then
        log_warning "No PVCs found to check consistency"
        return 1
    fi
    
    local first_sc="${storage_classes[0]}"
    local consistent=true
    
    for sc in "${storage_classes[@]}"; do
        if [[ "$sc" != "$first_sc" ]]; then
            consistent=false
            break
        fi
    done
    
    if [[ "$consistent" == "true" ]]; then
        log_success "✓ All PVCs use consistent storage class: $first_sc"
        return 0
    else
        log_warning "⚠ Inconsistent storage classes detected:"
        for pvc in "${pvcs[@]}"; do
            if resource_exists pvc "$pvc" "$NAMESPACE"; then
                local sc
                sc=$(get_pvc_storage_class "$pvc" "$NAMESPACE")
                echo "    $pvc: $sc"
            fi
        done
        return 1
    fi
}

# Function to check storage usage
check_storage_usage() {
    log_info "Storage Usage Information:"
    echo "=========================="
    
    # Get PV information for bound PVCs
    local pvcs=("postgresql-primary-pvc" "postgresql-standby-pvc" "airflow-dags-pvc" "airflow-logs-pvc" "airflow-config-pvc")
    
    for pvc in "${pvcs[@]}"; do
        if resource_exists pvc "$pvc" "$NAMESPACE"; then
            local status
            status=$(get_pvc_status "$pvc" "$NAMESPACE")
            
            if [[ "$status" == "Bound" ]]; then
                local pv_name
                pv_name=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
                
                if [[ -n "$pv_name" ]]; then
                    echo "  $pvc -> $pv_name:"
                    kubectl get pv "$pv_name" -o custom-columns="CAPACITY:.spec.capacity.storage,ACCESS:.spec.accessModes,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase" --no-headers | sed 's/^/    /'
                else
                    echo "  $pvc: No PV information available"
                fi
            fi
        fi
    done
    echo
}

# Function to provide recommendations
provide_recommendations() {
    log_info "Recommendations:"
    echo "================"
    
    # Check if using recommended storage class
    local using_nfs=false
    local pvcs=("postgresql-primary-pvc" "airflow-dags-pvc" "airflow-logs-pvc")
    
    for pvc in "${pvcs[@]}"; do
        if resource_exists pvc "$pvc" "$NAMESPACE"; then
            local sc
            sc=$(get_pvc_storage_class "$pvc" "$NAMESPACE")
            if [[ "$sc" == "nfs-client" ]]; then
                using_nfs=true
                break
            fi
        fi
    done
    
    if [[ "$using_nfs" == "true" ]]; then
        log_success "✓ Using recommended NFS storage class"
    else
        log_warning "⚠ Consider using NFS storage class for production workloads"
        echo "    - Provides ReadWriteMany access mode"
        echo "    - Better performance for multi-pod access"
        echo "    - Shared storage for DAGs and logs"
    fi
    
    # Check for missing optional PVCs
    if ! resource_exists pvc "airflow-config-pvc" "$NAMESPACE"; then
        log_info "ℹ Consider creating airflow-config-pvc for configuration persistence"
    fi
    
    # Storage size recommendations
    echo
    log_info "Storage Size Guidelines:"
    echo "  - PostgreSQL: 100Gi (current production workload)"
    echo "  - Airflow DAGs: 50Gi (for DAG files and dependencies)"
    echo "  - Airflow Logs: 200Gi (for task execution logs)"
    echo "  - Airflow Config: 10Gi (for configuration and plugins)"
    
    echo
    log_info "Troubleshooting Commands:"
    echo "  - Fix PostgreSQL storage: ./fix-postgresql-storage.sh"
    echo "  - Deploy Airflow storage: ./deploy-airflow-storage.sh"
    echo "  - Quick storage fix: ./quick-fix-storage.sh"
    echo "  - Check PVC events: kubectl describe pvc <pvc-name> -n $NAMESPACE"
    echo "  - Check storage class: kubectl describe storageclass <class-name>"
}

# Function to run comprehensive check
run_comprehensive_check() {
    echo "=========================================="
    echo "Airflow Storage Configuration Check"
    echo "=========================================="
    echo
    
    local overall_status=0
    
    # Check storage classes
    check_storage_classes
    echo
    
    # Check PostgreSQL storage
    if ! check_postgresql_storage; then
        overall_status=1
    fi
    echo
    
    # Check Airflow storage
    if ! check_airflow_storage; then
        overall_status=1
    fi
    echo
    
    # Check consistency
    if ! check_storage_consistency; then
        overall_status=1
    fi
    echo
    
    # Check usage
    check_storage_usage
    
    # Provide recommendations
    provide_recommendations
    
    echo
    echo "=========================================="
    if [[ $overall_status -eq 0 ]]; then
        log_success "✅ Storage configuration looks good!"
    else
        log_warning "⚠️  Storage configuration needs attention"
        echo
        log_info "Next steps:"
        echo "1. Review the warnings and errors above"
        echo "2. Run appropriate fix scripts"
        echo "3. Re-run this check to verify fixes"
    fi
    echo "=========================================="
    
    return $overall_status
}

# Main execution
main() {
    case "${1:-check}" in
        "check"|"status")
            run_comprehensive_check
            ;;
        "storage-classes"|"sc")
            check_storage_classes
            ;;
        "postgresql"|"postgres"|"pg")
            check_postgresql_storage
            ;;
        "airflow")
            check_airflow_storage
            ;;
        "consistency")
            check_storage_consistency
            ;;
        "usage")
            check_storage_usage
            ;;
        "recommendations"|"rec")
            provide_recommendations
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo
            echo "Commands:"
            echo "  check              - Run comprehensive storage check (default)"
            echo "  status             - Alias for check"
            echo "  storage-classes    - Check available storage classes"
            echo "  postgresql         - Check PostgreSQL storage only"
            echo "  airflow            - Check Airflow storage only"
            echo "  consistency        - Check storage class consistency"
            echo "  usage              - Show storage usage information"
            echo "  recommendations    - Show recommendations"
            echo "  help               - Show this help message"
            echo
            echo "This script provides comprehensive information about"
            echo "the storage configuration for the Airflow deployment."
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"