#!/bin/bash

# Deploy Airflow using Helm chart with HA configuration
# This script implements task 5: Deploy Airflow using Helm chart with HA configuration
# Requirements: 1.1, 1.2, 1.3, 1.4, 5.4

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="airflow"
RELEASE_NAME="airflow"
CHART_VERSION="1.11.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/airflow-values.yaml"
STORAGE_CLASS=""  # Will be detected automatically

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for pods to be ready
wait_for_pods() {
    local label_selector="$1"
    local timeout="${2:-300}"
    
    print_status "Waiting for pods with selector '$label_selector' to be ready (timeout: ${timeout}s)..."
    
    if kubectl wait --for=condition=Ready pods -l "$label_selector" -n "$NAMESPACE" --timeout="${timeout}s"; then
        print_success "Pods are ready"
        return 0
    else
        print_error "Timeout waiting for pods to be ready"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command_exists kubectl; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command_exists helm; then
        print_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_error "Namespace '$NAMESPACE' does not exist. Please run the RBAC setup first."
        exit 1
    fi
    
    # Check if values file exists
    if [[ ! -f "$VALUES_FILE" ]]; then
        print_error "Values file not found: $VALUES_FILE"
        exit 1
    fi
    
    # Check storage class availability
    check_storage_class
    
    # Check if PostgreSQL is running
    check_postgresql_deployment
    
    # Check if Redis is running
    if ! kubectl get statefulset redis -n "$NAMESPACE" >/dev/null 2>&1; then
        print_error "Redis is not deployed. Please run Redis setup first."
        exit 1
    fi
    
    # Check if storage PVCs exist and are bound
    check_storage_pvcs
    
    print_success "All prerequisites met"
}

# Function to check storage class availability
check_storage_class() {
    print_status "Checking storage class availability..."
    
    if kubectl get storageclass nfs-client >/dev/null 2>&1; then
        print_success "✓ NFS storage class (nfs-client) is available"
        STORAGE_CLASS="nfs-client"
    elif kubectl get storageclass local-path >/dev/null 2>&1; then
        print_warning "⚠ Using local-path storage (NFS preferred for production)"
        STORAGE_CLASS="local-path"
    else
        print_error "✗ No suitable storage class found (nfs-client or local-path)"
        print_error "Please install a storage provisioner before deploying Airflow"
        exit 1
    fi
}

# Function to check PostgreSQL deployment
check_postgresql_deployment() {
    print_status "Checking PostgreSQL deployment..."
    
    # Check if PostgreSQL StatefulSet exists (either name format)
    if kubectl get statefulset postgresql-primary -n "$NAMESPACE" >/dev/null 2>&1; then
        print_success "✓ PostgreSQL primary StatefulSet found"
        
        # Check if PostgreSQL pods are ready
        local ready_pods
        ready_pods=$(kubectl get pods -n "$NAMESPACE" -l app=postgresql,component=primary --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$ready_pods" -gt 0 ]]; then
            print_success "✓ PostgreSQL primary is running"
        else
            print_warning "⚠ PostgreSQL primary exists but may not be ready"
        fi
        
        # Check PostgreSQL PVCs
        if kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" >/dev/null 2>&1; then
            local pvc_status
            pvc_status=$(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            if [[ "$pvc_status" == "Bound" ]]; then
                print_success "✓ PostgreSQL primary PVC is bound"
            else
                print_warning "⚠ PostgreSQL primary PVC status: $pvc_status"
            fi
        else
            print_warning "⚠ PostgreSQL primary PVC not found"
        fi
    else
        print_error "PostgreSQL primary is not deployed. Please run PostgreSQL setup first."
        print_error "Use: ./deploy-postgresql.sh or ./fix-postgresql-storage.sh"
        exit 1
    fi
}

# Function to check storage PVCs
check_storage_pvcs() {
    print_status "Checking Airflow storage PVCs..."
    
    local missing_pvcs=()
    local pvcs=("airflow-dags-pvc" "airflow-logs-pvc")
    
    for pvc in "${pvcs[@]}"; do
        if kubectl get pvc "$pvc" -n "$NAMESPACE" >/dev/null 2>&1; then
            local pvc_status
            pvc_status=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            if [[ "$pvc_status" == "Bound" ]]; then
                print_success "✓ $pvc is bound"
            else
                print_warning "⚠ $pvc status: $pvc_status"
                missing_pvcs+=("$pvc")
            fi
        else
            print_warning "⚠ $pvc not found"
            missing_pvcs+=("$pvc")
        fi
    done
    
    # Check optional config PVC
    if kubectl get pvc airflow-config-pvc -n "$NAMESPACE" >/dev/null 2>&1; then
        local pvc_status
        pvc_status=$(kubectl get pvc airflow-config-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        if [[ "$pvc_status" == "Bound" ]]; then
            print_success "✓ airflow-config-pvc is bound"
        else
            print_warning "⚠ airflow-config-pvc status: $pvc_status"
        fi
    else
        print_status "ℹ airflow-config-pvc not found (optional)"
    fi
    
    if [[ ${#missing_pvcs[@]} -gt 0 ]]; then
        print_error "Missing or unbound PVCs: ${missing_pvcs[*]}"
        print_error "Please run storage setup first: ./deploy-airflow-storage.sh"
        exit 1
    fi
}

# Function to add Airflow Helm repository
add_helm_repo() {
    print_status "Adding Apache Airflow Helm repository..."
    
    if helm repo list | grep -q "apache-airflow"; then
        print_status "Apache Airflow repository already exists, updating..."
        helm repo update apache-airflow
    else
        helm repo add apache-airflow https://airflow.apache.org
        helm repo update
    fi
    
    print_success "Helm repository configured"
}

# Function to validate Helm values
validate_values() {
    print_status "Validating Helm values..."
    
    # Use helm template to validate the values file
    if helm template "$RELEASE_NAME" apache-airflow/airflow \
        --version "$CHART_VERSION" \
        --namespace "$NAMESPACE" \
        --values "$VALUES_FILE" \
        --dry-run >/dev/null 2>&1; then
        print_success "Helm values validation passed"
    else
        print_error "Helm values validation failed"
        exit 1
    fi
}

# Function to deploy Airflow
deploy_airflow() {
    print_status "Deploying Airflow with Helm..."
    
    # Check if release already exists
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_status "Airflow release exists, upgrading..."
        helm upgrade "$RELEASE_NAME" apache-airflow/airflow \
            --version "$CHART_VERSION" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --wait \
            --timeout 10m
    else
        print_status "Installing new Airflow release..."
        helm install "$RELEASE_NAME" apache-airflow/airflow \
            --version "$CHART_VERSION" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --wait \
            --timeout 10m
    fi
    
    print_success "Airflow deployment completed"
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying Airflow deployment..."
    
    # Check webserver pods (should be 2 replicas)
    print_status "Checking webserver pods..."
    local webserver_pods
    webserver_pods=$(kubectl get pods -n "$NAMESPACE" -l component=webserver --no-headers | wc -l)
    if [[ "$webserver_pods" -eq 2 ]]; then
        print_success "Webserver has 2 replicas as expected"
    else
        print_warning "Webserver has $webserver_pods replicas (expected 2)"
    fi
    
    # Check scheduler pods (should be 2 replicas)
    print_status "Checking scheduler pods..."
    local scheduler_pods
    scheduler_pods=$(kubectl get pods -n "$NAMESPACE" -l component=scheduler --no-headers | wc -l)
    if [[ "$scheduler_pods" -eq 2 ]]; then
        print_success "Scheduler has 2 replicas as expected"
    else
        print_warning "Scheduler has $scheduler_pods replicas (expected 2)"
    fi
    
    # Check worker pods (should be at least 2)
    print_status "Checking worker pods..."
    local worker_pods
    worker_pods=$(kubectl get pods -n "$NAMESPACE" -l component=worker --no-headers | wc -l)
    if [[ "$worker_pods" -ge 2 ]]; then
        print_success "Workers have $worker_pods replicas (minimum 2)"
    else
        print_warning "Workers have $worker_pods replicas (expected minimum 2)"
    fi
    
    # Wait for all pods to be ready
    wait_for_pods "app.kubernetes.io/name=airflow" 600
    
    # Check service endpoints
    print_status "Checking service endpoints..."
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=airflow
    
    print_success "Deployment verification completed"
}

# Function to display connection information
display_connection_info() {
    print_status "Airflow connection information:"
    echo
    echo "Namespace: $NAMESPACE"
    echo "Release: $RELEASE_NAME"
    echo
    echo "Services:"
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=airflow -o wide
    echo
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=airflow -o wide
    echo
    echo "To access Airflow webserver locally:"
    echo "kubectl port-forward svc/airflow-webserver 8080:8080 -n $NAMESPACE"
    echo "Then open: http://localhost:8080"
    echo
    echo "Default credentials (if not using external auth):"
    echo "Username: admin"
    echo "Password: admin"
    echo
}

# Function to run health checks
run_health_checks() {
    print_status "Running health checks..."
    
    # Check if webserver is responding
    print_status "Testing webserver health endpoint..."
    if kubectl exec -n "$NAMESPACE" deployment/airflow-webserver -- \
        curl -f http://localhost:8080/health >/dev/null 2>&1; then
        print_success "Webserver health check passed"
    else
        print_warning "Webserver health check failed (may still be starting)"
    fi
    
    # Check scheduler logs for any errors
    print_status "Checking scheduler logs for errors..."
    local error_count
    error_count=$(kubectl logs -n "$NAMESPACE" -l component=scheduler --tail=100 | grep -i error | wc -l)
    if [[ "$error_count" -eq 0 ]]; then
        print_success "No errors found in scheduler logs"
    else
        print_warning "Found $error_count error messages in scheduler logs"
    fi
    
    print_success "Health checks completed"
}

# Function to fix storage issues automatically
fix_storage_issues() {
    print_status "Checking for storage issues and applying fixes if needed..."
    
    # Check if PostgreSQL storage needs fixing
    local postgres_needs_fix=false
    
    # Check if PostgreSQL PVC exists but is not bound
    if kubectl get pvc -n "$NAMESPACE" | grep postgresql | grep -q Pending; then
        print_warning "Found pending PostgreSQL PVCs"
        postgres_needs_fix=true
    fi
    
    # Check if PostgreSQL pods are failing due to storage
    local failed_postgres_pods
    failed_postgres_pods=$(kubectl get pods -n "$NAMESPACE" -l app=postgresql --no-headers 2>/dev/null | grep -c "Pending\|ContainerCreating\|Init:" || echo "0")
    if [[ "$failed_postgres_pods" -gt 0 ]]; then
        print_warning "Found PostgreSQL pods with potential storage issues"
        postgres_needs_fix=true
    fi
    
    # Apply storage fixes if needed
    if [[ "$postgres_needs_fix" == "true" ]]; then
        print_status "Applying PostgreSQL storage fixes..."
        if [[ -f "$SCRIPT_DIR/fix-postgresql-storage.sh" ]]; then
            "$SCRIPT_DIR/fix-postgresql-storage.sh"
        elif [[ -f "$SCRIPT_DIR/quick-fix-storage.sh" ]]; then
            "$SCRIPT_DIR/quick-fix-storage.sh"
        else
            print_warning "Storage fix scripts not found, manual intervention may be required"
        fi
    fi
    
    # Check if Airflow storage PVCs need to be created
    local airflow_pvcs=("airflow-dags-pvc" "airflow-logs-pvc")
    local missing_airflow_pvcs=()
    
    for pvc in "${airflow_pvcs[@]}"; do
        if ! kubectl get pvc "$pvc" -n "$NAMESPACE" >/dev/null 2>&1; then
            missing_airflow_pvcs+=("$pvc")
        fi
    done
    
    if [[ ${#missing_airflow_pvcs[@]} -gt 0 ]]; then
        print_status "Creating missing Airflow storage PVCs..."
        if [[ -f "$SCRIPT_DIR/deploy-airflow-storage.sh" ]]; then
            "$SCRIPT_DIR/deploy-airflow-storage.sh"
        else
            print_warning "Airflow storage deployment script not found"
        fi
    fi
    
    print_success "Storage issue check completed"
}

# Function to validate storage configuration
validate_storage_configuration() {
    print_status "Validating storage configuration..."
    
    # Check storage class consistency
    local postgres_storage_class=""
    local airflow_storage_class=""
    
    # Get PostgreSQL PVC storage class
    if kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" >/dev/null 2>&1; then
        postgres_storage_class=$(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.spec.storageClassName}')
    fi
    
    # Get Airflow PVC storage class
    if kubectl get pvc airflow-dags-pvc -n "$NAMESPACE" >/dev/null 2>&1; then
        airflow_storage_class=$(kubectl get pvc airflow-dags-pvc -n "$NAMESPACE" -o jsonpath='{.spec.storageClassName}')
    fi
    
    # Validate consistency
    if [[ -n "$postgres_storage_class" && -n "$airflow_storage_class" ]]; then
        if [[ "$postgres_storage_class" == "$airflow_storage_class" ]]; then
            print_success "✓ Storage classes are consistent: $postgres_storage_class"
            STORAGE_CLASS="$postgres_storage_class"
        else
            print_warning "⚠ Storage class mismatch: PostgreSQL($postgres_storage_class) vs Airflow($airflow_storage_class)"
            STORAGE_CLASS="$postgres_storage_class"  # Prefer PostgreSQL storage class
        fi
    elif [[ -n "$postgres_storage_class" ]]; then
        print_status "Using PostgreSQL storage class: $postgres_storage_class"
        STORAGE_CLASS="$postgres_storage_class"
    elif [[ -n "$airflow_storage_class" ]]; then
        print_status "Using Airflow storage class: $airflow_storage_class"
        STORAGE_CLASS="$airflow_storage_class"
    fi
    
    # Display storage summary
    print_status "Storage configuration summary:"
    echo "  Storage Class: ${STORAGE_CLASS:-auto-detected}"
    echo "  PostgreSQL PVCs:"
    kubectl get pvc -n "$NAMESPACE" | grep postgresql | sed 's/^/    /' || echo "    None found"
    echo "  Airflow PVCs:"
    kubectl get pvc -n "$NAMESPACE" | grep airflow | sed 's/^/    /' || echo "    None found"
    
    print_success "Storage configuration validation completed"
}

# Main execution
main() {
    echo "=========================================="
    echo "Airflow Helm Deployment Script"
    echo "Task 5: Deploy Airflow using Helm chart with HA configuration"
    echo "=========================================="
    echo
    
    # Pre-deployment checks and fixes
    validate_storage_configuration
    fix_storage_issues
    check_prerequisites
    
    # Deployment process
    add_helm_repo
    validate_values
    deploy_airflow
    verify_deployment
    run_health_checks
    display_connection_info
    
    echo
    print_success "Airflow deployment completed successfully!"
    echo
    echo "Storage Information:"
    echo "  Storage Class Used: ${STORAGE_CLASS:-auto-detected}"
    echo "  PostgreSQL Storage: $(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo 'Not found')"
    echo "  Airflow DAGs Storage: $(kubectl get pvc airflow-dags-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo 'Not found')"
    echo "  Airflow Logs Storage: $(kubectl get pvc airflow-logs-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo 'Not found')"
    echo
    echo "Next steps:"
    echo "1. Configure Vault integration (Task 6)"
    echo "2. Set up Ingress and TLS (Task 7)"
    echo "3. Configure horizontal pod autoscaling (Task 8)"
    echo "4. Implement network policies (Task 9)"
    echo
    echo "Troubleshooting:"
    echo "  - Check storage: kubectl get pvc -n $NAMESPACE"
    echo "  - Check pods: kubectl get pods -n $NAMESPACE"
    echo "  - Fix storage issues: ./fix-postgresql-storage.sh"
    echo "  - Deploy missing storage: ./deploy-airflow-storage.sh"
}

# Function to show help
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --fix-storage    Force storage issue detection and fixes"
    echo "  --skip-storage   Skip storage validation and fixes"
    echo "  --help, -h       Show this help message"
    echo
    echo "This script deploys Airflow using Helm with HA configuration."
    echo "It automatically detects and fixes common storage issues."
    echo
    echo "Prerequisites:"
    echo "  - Kubernetes cluster with kubectl access"
    echo "  - Helm 3.x installed"
    echo "  - Airflow namespace created (./deploy-airflow-rbac.sh)"
    echo "  - PostgreSQL deployed (./deploy-postgresql.sh)"
    echo "  - Redis deployed (./deploy-redis.sh)"
    echo "  - Storage configured (./deploy-airflow-storage.sh)"
}

# Parse command line arguments
FORCE_STORAGE_FIX=false
SKIP_STORAGE_CHECK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix-storage)
            FORCE_STORAGE_FIX=true
            shift
            ;;
        --skip-storage)
            SKIP_STORAGE_CHECK=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Update main function to handle options
main_with_options() {
    echo "=========================================="
    echo "Airflow Helm Deployment Script"
    echo "Task 5: Deploy Airflow using Helm chart with HA configuration"
    echo "=========================================="
    echo
    
    # Pre-deployment checks and fixes
    if [[ "$SKIP_STORAGE_CHECK" != "true" ]]; then
        validate_storage_configuration
        if [[ "$FORCE_STORAGE_FIX" == "true" ]]; then
            print_status "Force fixing storage issues..."
            fix_storage_issues
        else
            fix_storage_issues
        fi
    else
        print_warning "Skipping storage validation and fixes"
    fi
    
    check_prerequisites
    
    # Deployment process
    add_helm_repo
    validate_values
    deploy_airflow
    verify_deployment
    run_health_checks
    display_connection_info
    
    echo
    print_success "Airflow deployment completed successfully!"
    echo
    echo "Storage Information:"
    echo "  Storage Class Used: ${STORAGE_CLASS:-auto-detected}"
    echo "  PostgreSQL Storage: $(kubectl get pvc postgresql-primary-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo 'Not found')"
    echo "  Airflow DAGs Storage: $(kubectl get pvc airflow-dags-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo 'Not found')"
    echo "  Airflow Logs Storage: $(kubectl get pvc airflow-logs-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo 'Not found')"
    echo
    echo "Next steps:"
    echo "1. Configure Vault integration (Task 6)"
    echo "2. Set up Ingress and TLS (Task 7)"
    echo "3. Configure horizontal pod autoscaling (Task 8)"
    echo "4. Implement network policies (Task 9)"
    echo
    echo "Troubleshooting:"
    echo "  - Check storage status: ./check-airflow-storage.sh"
    echo "  - Check pods: kubectl get pods -n $NAMESPACE"
    echo "  - Fix storage issues: ./fix-postgresql-storage.sh"
    echo "  - Deploy missing storage: ./deploy-airflow-storage.sh"
    echo "  - Quick storage fix: ./quick-fix-storage.sh"
}

# Run main function with options
main_with_options