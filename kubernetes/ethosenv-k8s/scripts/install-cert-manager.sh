#!/bin/bash

# Install cert-manager for SSL certificate management
# This script installs cert-manager if it's not already present

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

echo "🔐 Installing cert-manager for SSL certificate management..."

# Check if cert-manager is already installed
if kubectl get namespace cert-manager >/dev/null 2>&1; then
    log_info "cert-manager namespace already exists, checking if it's running..."
    
    if kubectl get pods -n cert-manager | grep -q "Running"; then
        log_success "cert-manager is already installed and running!"
        
        # Still apply the ClusterIssuer in case it's not configured
        log_info "Applying ClusterIssuer configuration..."
        kubectl apply -f ../07-cert-manager-issuer.yaml
        
        exit 0
    else
        log_warning "cert-manager namespace exists but pods are not running. Continuing with installation..."
    fi
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

log_info "Installing cert-manager..."

# Install cert-manager using kubectl
log_info "Creating cert-manager namespace and CRDs..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

log_info "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager

log_success "cert-manager installed successfully!"

# Apply the ClusterIssuer
log_info "Applying ClusterIssuer for Let's Encrypt..."
kubectl apply -f ../07-cert-manager-issuer.yaml

log_success "ClusterIssuer configured!"

echo ""
log_info "📋 Verification Commands:"
echo "kubectl get pods -n cert-manager"
echo "kubectl get clusterissuer"
echo "kubectl describe clusterissuer letsencrypt-prod"

echo ""
log_info "🔍 Current Status:"
kubectl get pods -n cert-manager

echo ""
log_success "✅ cert-manager installation completed!"
log_info "You can now deploy SSL certificates using the ClusterIssuer 'letsencrypt-prod'"