#!/bin/bash

# Deploy Airflow Worker Horizontal Pod Autoscaler
# This script implements requirements 5.1, 5.2, 5.3, 5.5, 5.6
# Automatically detects available metrics APIs and deploys appropriate HPA configuration

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

# Function to check if a resource exists
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

# Function to check if API is available
api_available() {
    local api="$1"
    kubectl get apiservices | grep -q "$api"
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local deployment="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    log_info "Waiting for deployment $deployment to be ready..."
    if kubectl wait --for=condition=available --timeout="${timeout}s" deployment/"$deployment" -n "$namespace"; then
        log_success "Deployment $deployment is ready"
        return 0
    else
        log_error "Deployment $deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting Airflow Worker HPA deployment..."
    
    # Check if namespace exists
    if ! resource_exists namespace "$NAMESPACE"; then
        log_error "Namespace $NAMESPACE does not exist. Please create it first."
        exit 1
    fi
    
    # Check if Airflow worker deployment exists
    if ! resource_exists deployment airflow-worker "$NAMESPACE"; then
        log_error "Airflow worker deployment not found in namespace $NAMESPACE"
        log_error "Please deploy Airflow first using the main deployment script"
        exit 1
    fi
    
    # Check metrics server availability
    if ! api_available "v1beta1.metrics.k8s.io"; then
        log_error "Metrics server is not available. HPA requires metrics server."
        log_error "Please install metrics server first."
        exit 1
    fi
    
    log_success "Metrics server is available"
    
    # Check for custom metrics API (prometheus-adapter)
    local use_custom_metrics=false
    if api_available "v1beta1.custom.metrics.k8s.io"; then
        log_success "Custom metrics API is available - will use advanced HPA with queue metrics"
        use_custom_metrics=true
    else
        log_warning "Custom metrics API not available - will use resource-based HPA only"
        log_info "To enable queue-based scaling, install prometheus-adapter"
    fi
    
    # Deploy Prometheus rules for custom metrics
    log_info "Deploying Airflow queue metrics configuration..."
    kubectl apply -f "$SCRIPT_DIR/airflow-queue-metrics.yaml"
    log_success "Queue metrics configuration deployed"
    
    # Remove any existing HPA configurations to avoid conflicts
    log_info "Cleaning up existing HPA configurations..."
    kubectl delete hpa airflow-worker-hpa -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete hpa airflow-worker-hpa-advanced -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete hpa airflow-worker-hpa-fallback -n "$NAMESPACE" 2>/dev/null || true
    
    # Deploy appropriate HPA configuration
    if [[ "$use_custom_metrics" == "true" ]]; then
        log_info "Deploying advanced HPA with custom metrics..."
        
        # Try to deploy advanced HPA, fall back to basic if custom metrics fail
        if kubectl apply -f "$SCRIPT_DIR/airflow-worker-hpa-advanced.yaml" 2>/dev/null; then
            # Remove the fallback HPA if advanced deployment succeeded
            kubectl delete hpa airflow-worker-hpa-fallback -n "$NAMESPACE" 2>/dev/null || true
            log_success "Advanced HPA with custom metrics deployed successfully"
        else
            log_warning "Failed to deploy advanced HPA, falling back to resource-based HPA"
            # Deploy fallback HPA
            kubectl delete hpa airflow-worker-hpa-advanced -n "$NAMESPACE" 2>/dev/null || true
            kubectl apply -f "$SCRIPT_DIR/airflow-worker-hpa-advanced.yaml" --validate=false
            # Apply only the fallback section
            kubectl get hpa airflow-worker-hpa-fallback -n "$NAMESPACE" >/dev/null 2>&1 || \
                kubectl apply -f <(kubectl apply -f "$SCRIPT_DIR/airflow-worker-hpa-advanced.yaml" --dry-run=client -o yaml | \
                    yq eval 'select(.metadata.name == "airflow-worker-hpa-fallback")')
            log_success "Fallback HPA deployed"
        fi
    else
        log_info "Deploying resource-based HPA..."
        # Deploy basic HPA
        kubectl apply -f "$SCRIPT_DIR/airflow-worker-hpa.yaml"
        log_success "Resource-based HPA deployed successfully"
    fi
    
    # Wait a moment for HPA to initialize
    sleep 10
    
    # Verify HPA status
    log_info "Checking HPA status..."
    local hpa_name
    if kubectl get hpa airflow-worker-hpa-advanced -n "$NAMESPACE" >/dev/null 2>&1; then
        hpa_name="airflow-worker-hpa-advanced"
    elif kubectl get hpa airflow-worker-hpa-fallback -n "$NAMESPACE" >/dev/null 2>&1; then
        hpa_name="airflow-worker-hpa-fallback"
    elif kubectl get hpa airflow-worker-hpa -n "$NAMESPACE" >/dev/null 2>&1; then
        hpa_name="airflow-worker-hpa"
    else
        log_error "No HPA found after deployment"
        exit 1
    fi
    
    # Display HPA status
    log_info "HPA Status:"
    kubectl get hpa "$hpa_name" -n "$NAMESPACE"
    
    # Display current worker pod count
    log_info "Current worker pods:"
    kubectl get pods -n "$NAMESPACE" -l component=worker
    
    # Display scaling events
    log_info "Recent HPA events:"
    kubectl describe hpa "$hpa_name" -n "$NAMESPACE" | tail -10
    
    log_success "Airflow Worker HPA deployment completed successfully!"
    
    # Display next steps
    echo
    log_info "Next steps:"
    echo "1. Monitor HPA scaling behavior: kubectl get hpa $hpa_name -n $NAMESPACE --watch"
    echo "2. Check worker pod scaling: kubectl get pods -n $NAMESPACE -l component=worker --watch"
    echo "3. View detailed HPA status: kubectl describe hpa $hpa_name -n $NAMESPACE"
    echo "4. Test scaling by submitting DAGs with multiple tasks"
    
    if [[ "$use_custom_metrics" == "false" ]]; then
        echo
        log_info "To enable queue-based scaling:"
        echo "1. Install prometheus-adapter in your cluster"
        echo "2. Re-run this script to deploy advanced HPA configuration"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi