#!/bin/bash

# Deploy Airflow Ingress and TLS Configuration
# This script implements task 7: Configure Ingress and TLS certificates
# Requirements: 4.2, 4.6, 7.1, 7.2

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

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

log_info "Starting Airflow Ingress and TLS deployment..."

# Step 1: Create ClusterIssuer for Let's Encrypt production certificates
log_info "Creating Let's Encrypt production ClusterIssuer..."
if kubectl get clusterissuer letsencrypt-prod &> /dev/null; then
    log_warning "ClusterIssuer 'letsencrypt-prod' already exists, skipping creation"
else
    kubectl apply -f airflow-cluster-issuer.yaml
    log_success "ClusterIssuer created successfully"
fi

# Step 2: Ensure airflow namespace exists
log_info "Ensuring airflow namespace exists..."
kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -
log_success "Airflow namespace ready"

# Step 3: Create TLS Certificate resource
log_info "Creating TLS certificate for Airflow..."
kubectl apply -f airflow-certificate.yaml
log_success "TLS certificate resource created"

# Step 4: Wait for certificate to be ready
log_info "Waiting for certificate to be issued (this may take a few minutes)..."
timeout=300  # 5 minutes timeout
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get certificate airflow-tls-certificate -n airflow -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        log_success "Certificate issued successfully"
        break
    fi
    
    if [ $((elapsed % 30)) -eq 0 ]; then
        log_info "Still waiting for certificate... (${elapsed}s elapsed)"
        # Show certificate status for debugging
        kubectl describe certificate airflow-tls-certificate -n airflow | grep -A 5 "Status:"
    fi
    
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    log_warning "Certificate issuance timed out, but continuing with deployment"
    log_info "You can check certificate status with: kubectl describe certificate airflow-tls-certificate -n airflow"
fi

# Step 5: Create Ingress with security middlewares
log_info "Creating Ingress with TLS and security configuration..."
kubectl apply -f airflow-ingress-tls.yaml
log_success "Ingress configuration applied"

# Step 6: Verify deployment
log_info "Verifying deployment..."

# Check if ingress was created
if kubectl get ingress airflow-tls -n airflow &> /dev/null; then
    log_success "Ingress created successfully"
    
    # Show ingress details
    log_info "Ingress details:"
    kubectl get ingress airflow-tls -n airflow -o wide
else
    log_error "Failed to create ingress"
    exit 1
fi

# Check if middlewares were created
log_info "Checking security middlewares..."
if kubectl get middleware security-headers -n airflow &> /dev/null; then
    log_success "Security headers middleware created"
else
    log_warning "Security headers middleware not found"
fi

if kubectl get middleware rate-limit -n airflow &> /dev/null; then
    log_success "Rate limiting middleware created"
else
    log_warning "Rate limiting middleware not found"
fi

# Check certificate status
log_info "Certificate status:"
kubectl get certificate airflow-tls-certificate -n airflow -o wide

# Check secret creation
if kubectl get secret airflow-tls-secret -n airflow &> /dev/null; then
    log_success "TLS secret created successfully"
else
    log_warning "TLS secret not yet created - certificate may still be pending"
fi

log_success "Airflow Ingress and TLS deployment completed!"
log_info ""
log_info "Next steps:"
log_info "1. Ensure DNS record for 'airflow.gray-beard.com' points to your cluster's external IP"
log_info "2. Wait for certificate to be fully issued if still pending"
log_info "3. Test access to https://airflow.gray-beard.com"
log_info ""
log_info "To check certificate status: kubectl describe certificate airflow-tls-certificate -n airflow"
log_info "To check ingress status: kubectl describe ingress airflow-tls -n airflow"