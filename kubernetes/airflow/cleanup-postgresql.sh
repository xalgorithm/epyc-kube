#!/bin/bash

# Cleanup PostgreSQL Components
# This script removes all PostgreSQL components to allow clean deployment

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

# Function to cleanup PostgreSQL StatefulSets
cleanup_statefulsets() {
    log_info "Cleaning up PostgreSQL StatefulSets..."
    
    local statefulsets=("postgresql-primary" "postgresql-standby")
    
    for sts in "${statefulsets[@]}"; do
        if resource_exists statefulset "$sts" "$NAMESPACE"; then
            log_info "Scaling down StatefulSet: $sts"
            kubectl scale statefulset "$sts" --replicas=0 -n "$NAMESPACE"
            
            # Wait for pods to be deleted
            kubectl wait --for=delete pod -l app=postgresql,component=${sts#postgresql-} -n "$NAMESPACE" --timeout=120s || true
            
            log_info "Deleting StatefulSet: $sts"
            kubectl delete statefulset "$sts" -n "$NAMESPACE" --ignore-not-found=true
            
            wait_for_deletion statefulset "$sts" "$NAMESPACE"
        else
            log_info "StatefulSet $sts not found"
        fi
    done
}

# Function to cleanup PostgreSQL Services
cleanup_services() {
    log_info "Cleaning up PostgreSQL Services..."
    
    local services=("postgresql-primary" "postgresql-standby" "postgresql-headless")
    
    for svc in "${services[@]}"; do
        if resource_exists service "$svc" "$NAMESPACE"; then
            log_info "Deleting Service: $svc"
            kubectl delete service "$svc" -n "$NAMESPACE" --ignore-not-found=true
            wait_for_deletion service "$svc" "$NAMESPACE"
        else
            log_info "Service $svc not found"
        fi
    done
}

# Function to cleanup PostgreSQL PVCs
cleanup_pvcs() {
    log_info "Cleaning up PostgreSQL PVCs..."
    
    # Get all PostgreSQL-related PVCs
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" -o name | grep postgresql || echo "")
    
    if [[ -n "$pvcs" ]]; then
        for pvc in $pvcs; do
            local pvc_name=${pvc#pvc/}
            log_info "Deleting PVC: $pvc_name"
            kubectl delete "$pvc" -n "$NAMESPACE" --ignore-not-found=true
        done
        
        # Wait for all PostgreSQL PVCs to be deleted
        log_info "Waiting for PostgreSQL PVCs to be deleted..."
        local timeout=60
        local count=0
        while kubectl get pvc -n "$NAMESPACE" | grep -q postgresql; do
            if [[ $count -ge $timeout ]]; then
                log_warning "Timeout waiting for PVCs deletion, some may still exist"
                break
            fi
            echo -n "."
            sleep 1
            count=$((count + 1))
        done
        echo
        log_success "PostgreSQL PVCs cleanup completed"
    else
        log_info "No PostgreSQL PVCs found"
    fi
}

# Function to cleanup PostgreSQL ConfigMaps
cleanup_configmaps() {
    log_info "Cleaning up PostgreSQL ConfigMaps..."
    
    local configmaps=("postgresql-config" "postgresql-scripts")
    
    for cm in "${configmaps[@]}"; do
        if resource_exists configmap "$cm" "$NAMESPACE"; then
            log_info "Deleting ConfigMap: $cm"
            kubectl delete configmap "$cm" -n "$NAMESPACE" --ignore-not-found=true
            wait_for_deletion configmap "$cm" "$NAMESPACE"
        else
            log_info "ConfigMap $cm not found"
        fi
    done
}

# Function to cleanup PostgreSQL Secrets
cleanup_secrets() {
    log_info "Cleaning up PostgreSQL Secrets..."
    
    local secrets=("postgresql-secret")
    
    for secret in "${secrets[@]}"; do
        if resource_exists secret "$secret" "$NAMESPACE"; then
            log_info "Deleting Secret: $secret"
            kubectl delete secret "$secret" -n "$NAMESPACE" --ignore-not-found=true
            wait_for_deletion secret "$secret" "$NAMESPACE"
        else
            log_info "Secret $secret not found"
        fi
    done
}

# Function to cleanup PostgreSQL Jobs and CronJobs
cleanup_jobs() {
    log_info "Cleaning up PostgreSQL Jobs and CronJobs..."
    
    # Delete any PostgreSQL-related jobs
    local jobs
    jobs=$(kubectl get jobs -n "$NAMESPACE" -o name | grep postgresql || echo "")
    
    if [[ -n "$jobs" ]]; then
        for job in $jobs; do
            local job_name=${job#job.batch/}
            log_info "Deleting Job: $job_name"
            kubectl delete job "$job_name" -n "$NAMESPACE" --ignore-not-found=true
        done
    fi
    
    # Delete any PostgreSQL-related cronjobs
    local cronjobs
    cronjobs=$(kubectl get cronjobs -n "$NAMESPACE" -o name | grep postgresql || echo "")
    
    if [[ -n "$cronjobs" ]]; then
        for cronjob in $cronjobs; do
            local cronjob_name=${cronjob#cronjob.batch/}
            log_info "Deleting CronJob: $cronjob_name"
            kubectl delete cronjob "$cronjob_name" -n "$NAMESPACE" --ignore-not-found=true
        done
    fi
}

# Function to cleanup monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up PostgreSQL monitoring resources..."
    
    # ServiceMonitors
    local servicemonitors
    servicemonitors=$(kubectl get servicemonitor -n "$NAMESPACE" -o name | grep postgresql || echo "")
    
    if [[ -n "$servicemonitors" ]]; then
        for sm in $servicemonitors; do
            local sm_name=${sm#servicemonitor.monitoring.coreos.com/}
            log_info "Deleting ServiceMonitor: $sm_name"
            kubectl delete servicemonitor "$sm_name" -n "$NAMESPACE" --ignore-not-found=true
        done
    fi
    
    # PrometheusRules
    local prometheusrules
    prometheusrules=$(kubectl get prometheusrule -n "$NAMESPACE" -o name | grep postgresql || echo "")
    
    if [[ -n "$prometheusrules" ]]; then
        for pr in $prometheusrules; do
            local pr_name=${pr#prometheusrule.monitoring.coreos.com/}
            log_info "Deleting PrometheusRule: $pr_name"
            kubectl delete prometheusrule "$pr_name" -n "$NAMESPACE" --ignore-not-found=true
        done
    fi
}

# Function to cleanup generated files
cleanup_generated_files() {
    log_info "Cleaning up generated PostgreSQL configuration files..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local generated_files=(
        "$script_dir/postgresql-storage-dynamic.yaml"
        "$script_dir/postgresql-deployment-temp.yaml"
    )
    
    for file in "${generated_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing generated file: $(basename "$file")"
            rm -f "$file"
        fi
    done
}

# Function to show current PostgreSQL resources
show_current_resources() {
    log_info "Current PostgreSQL resources in namespace $NAMESPACE:"
    echo "=================================================="
    
    echo ""
    log_info "Pods:"
    kubectl get pods -n "$NAMESPACE" | grep postgresql || echo "  No PostgreSQL pods found"
    
    echo ""
    log_info "StatefulSets:"
    kubectl get statefulsets -n "$NAMESPACE" | grep postgresql || echo "  No PostgreSQL StatefulSets found"
    
    echo ""
    log_info "Services:"
    kubectl get services -n "$NAMESPACE" | grep postgresql || echo "  No PostgreSQL Services found"
    
    echo ""
    log_info "PVCs:"
    kubectl get pvc -n "$NAMESPACE" | grep postgresql || echo "  No PostgreSQL PVCs found"
    
    echo ""
    log_info "Secrets:"
    kubectl get secrets -n "$NAMESPACE" | grep postgresql || echo "  No PostgreSQL Secrets found"
    
    echo ""
    log_info "ConfigMaps:"
    kubectl get configmaps -n "$NAMESPACE" | grep postgresql || echo "  No PostgreSQL ConfigMaps found"
    
    echo ""
}

# Function to perform comprehensive cleanup
comprehensive_cleanup() {
    log_info "Starting comprehensive PostgreSQL cleanup..."
    echo "============================================="
    
    # Show current state
    show_current_resources
    
    # Perform cleanup in order
    cleanup_jobs
    cleanup_statefulsets
    cleanup_services
    cleanup_pvcs
    cleanup_configmaps
    cleanup_secrets
    cleanup_monitoring
    cleanup_generated_files
    
    # Wait a moment for final cleanup
    sleep 5
    
    # Show final state
    echo ""
    log_success "PostgreSQL cleanup completed!"
    echo ""
    show_current_resources
    
    echo ""
    log_info "PostgreSQL components have been removed."
    log_info "You can now run './deploy-postgresql.sh' for a clean deployment."
}

# Function to show help
show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  cleanup     - Perform comprehensive PostgreSQL cleanup (default)"
    echo "  status      - Show current PostgreSQL resources"
    echo "  statefulsets - Cleanup StatefulSets only"
    echo "  services    - Cleanup Services only"
    echo "  pvcs        - Cleanup PVCs only"
    echo "  secrets     - Cleanup Secrets only"
    echo "  configmaps  - Cleanup ConfigMaps only"
    echo "  monitoring  - Cleanup monitoring resources only"
    echo "  help        - Show this help message"
    echo ""
    echo "This script removes all PostgreSQL components from the '$NAMESPACE' namespace"
    echo "to allow for a clean deployment using deploy-postgresql.sh"
}

# Main execution
main() {
    case "${1:-cleanup}" in
        "cleanup")
            comprehensive_cleanup
            ;;
        "status")
            show_current_resources
            ;;
        "statefulsets")
            cleanup_statefulsets
            ;;
        "services")
            cleanup_services
            ;;
        "pvcs")
            cleanup_pvcs
            ;;
        "secrets")
            cleanup_secrets
            ;;
        "configmaps")
            cleanup_configmaps
            ;;
        "monitoring")
            cleanup_monitoring
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"