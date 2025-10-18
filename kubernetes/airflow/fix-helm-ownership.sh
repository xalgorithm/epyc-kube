#!/bin/bash

# Fix Helm Ownership Issues
# This script fixes existing Kubernetes resources to be managed by Helm

set -euo pipefail

NAMESPACE="airflow"
RELEASE_NAME="airflow"

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

echo "🔧 Fixing Helm ownership issues for Airflow resources..."

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace $NAMESPACE does not exist"
    exit 1
fi

# Function to add Helm labels and annotations to a resource
fix_resource_ownership() {
    local resource_type=$1
    local resource_name=$2
    
    log_info "Fixing ownership for $resource_type/$resource_name"
    
    # Check if resource exists
    if ! kubectl get "$resource_type" "$resource_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_warning "$resource_type/$resource_name does not exist, skipping"
        return 0
    fi
    
    # Add Helm labels
    kubectl label "$resource_type" "$resource_name" -n "$NAMESPACE" \
        app.kubernetes.io/managed-by=Helm \
        --overwrite >/dev/null 2>&1 || true
    
    # Add Helm annotations
    kubectl annotate "$resource_type" "$resource_name" -n "$NAMESPACE" \
        meta.helm.sh/release-name="$RELEASE_NAME" \
        meta.helm.sh/release-namespace="$NAMESPACE" \
        --overwrite >/dev/null 2>&1 || true
    
    log_success "Fixed ownership for $resource_type/$resource_name"
}

# Function to delete conflicting resources that Helm will recreate
delete_conflicting_resource() {
    local resource_type=$1
    local resource_name=$2
    
    log_warning "Deleting conflicting $resource_type/$resource_name (Helm will recreate it)"
    
    if kubectl get "$resource_type" "$resource_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        kubectl delete "$resource_type" "$resource_name" -n "$NAMESPACE" --ignore-not-found=true
        log_success "Deleted $resource_type/$resource_name"
    else
        log_info "$resource_type/$resource_name does not exist"
    fi
}

# List of resources that might conflict with Helm
SERVICEACCOUNTS=(
    "airflow-scheduler"
    "airflow-webserver"
    "airflow-worker"
    "airflow-flower"
    "airflow-statsd"
    "airflow-triggerer"
    "airflow-dag-processor"
    "airflow-api-server"
    "airflow-create-user-job"
    "airflow-migrate-database-job"
)

CONFIGMAPS=(
    "airflow-config"
    "airflow-statsd-mapping"
)

SECRETS=(
    "airflow-webserver-secret"
    "airflow-database-secret"
    "airflow-redis-secret"
    "airflow-connections-secret"
)

SERVICES=(
    "airflow-webserver"
    "airflow-flower"
    "airflow-statsd-exporter"
)

DEPLOYMENTS=(
    "airflow-webserver"
    "airflow-flower"
    "airflow-statsd-exporter"
)

STATEFULSETS=(
    "airflow-scheduler"
    "airflow-worker"
)

# Check what approach to take
echo ""
log_info "Checking existing resources..."

# Count existing resources
existing_count=0
for sa in "${SERVICEACCOUNTS[@]}"; do
    if kubectl get serviceaccount "$sa" -n "$NAMESPACE" >/dev/null 2>&1; then
        existing_count=$((existing_count + 1))
    fi
done

echo ""
if [[ $existing_count -gt 0 ]]; then
    log_warning "Found $existing_count existing ServiceAccounts that may conflict with Helm"
    echo ""
    echo "Choose an approach:"
    echo "1. Delete conflicting resources (Recommended - Helm will recreate them)"
    echo "2. Add Helm ownership labels/annotations (May not work for all resources)"
    echo "3. Cancel and handle manually"
    echo ""
    read -p "Enter your choice (1-3): " -r choice
    
    case $choice in
        1)
            log_info "Deleting conflicting resources..."
            
            # Delete ServiceAccounts
            for sa in "${SERVICEACCOUNTS[@]}"; do
                delete_conflicting_resource "serviceaccount" "$sa"
            done
            
            # Delete other potentially conflicting resources
            for cm in "${CONFIGMAPS[@]}"; do
                delete_conflicting_resource "configmap" "$cm"
            done
            
            # Note: Don't delete secrets as they contain important data
            log_warning "Keeping secrets (they contain important data)"
            
            # Delete services that Helm will recreate
            for svc in "${SERVICES[@]}"; do
                delete_conflicting_resource "service" "$svc"
            done
            
            # Delete deployments that Helm will recreate
            for deploy in "${DEPLOYMENTS[@]}"; do
                delete_conflicting_resource "deployment" "$deploy"
            done
            
            # Delete StatefulSets that Helm will recreate
            for sts in "${STATEFULSETS[@]}"; do
                delete_conflicting_resource "statefulset" "$sts"
            done
            
            log_success "Conflicting resources deleted. Helm can now manage them."
            ;;
            
        2)
            log_info "Adding Helm ownership labels and annotations..."
            
            # Fix ServiceAccounts
            for sa in "${SERVICEACCOUNTS[@]}"; do
                fix_resource_ownership "serviceaccount" "$sa"
            done
            
            # Fix other resources
            for cm in "${CONFIGMAPS[@]}"; do
                fix_resource_ownership "configmap" "$cm"
            done
            
            for secret in "${SECRETS[@]}"; do
                fix_resource_ownership "secret" "$secret"
            done
            
            log_success "Added Helm ownership metadata to existing resources."
            log_warning "Note: This approach may not work for all resource types."
            ;;
            
        3)
            log_info "Operation cancelled by user"
            exit 0
            ;;
            
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
else
    log_info "No conflicting resources found"
fi

echo ""
log_success "✅ Helm ownership issues resolved!"

echo ""
log_info "📋 Next Steps:"
echo "1. Run the Airflow deployment: ./deploy-airflow.sh"
echo "2. Or run Helm install directly:"
echo "   helm install airflow apache-airflow/airflow -f airflow-values.yaml -n airflow"

echo ""
log_info "🔍 Verification Commands:"
echo "kubectl get all -n $NAMESPACE"
echo "helm list -n $NAMESPACE"