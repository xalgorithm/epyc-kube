#!/bin/bash

# Deploy WordPress to Kubernetes
# This script deploys the WordPress application to the ethosenv namespace

set -euo pipefail

NAMESPACE="ethosenv"
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

echo "🚀 Deploying WordPress to Kubernetes..."

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

# Deploy in order
log_info "Step 1: Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/01-namespace.yaml"

log_info "Step 2: Creating secrets..."
kubectl apply -f "$SCRIPT_DIR/02-secrets.yaml"

log_info "Step 3: Creating storage..."
kubectl apply -f "$SCRIPT_DIR/03-storage.yaml"

# Wait for PVCs to be bound
#log_info "Waiting for PVCs to be bound..."
#kubectl wait --for=condition=bound pvc/mysql-pvc -n "$NAMESPACE" --timeout=120s
#kubectl wait --for=condition=bound pvc/wordpress-pvc -n "$NAMESPACE" --timeout=120s

log_info "Step 4: Deploying MySQL..."
kubectl apply -f "$SCRIPT_DIR/04-mysql-deployment.yaml"

# Wait for MySQL to be ready
log_info "Waiting for MySQL to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/mysql -n "$NAMESPACE"

log_info "Step 5: Deploying WordPress..."
kubectl apply -f "$SCRIPT_DIR/05-wordpress-deployment.yaml"

# Wait for WordPress to be ready
log_info "Waiting for WordPress to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/wordpress -n "$NAMESPACE"

log_info "Step 6: Setting up SSL certificates..."
# Check if cert-manager is installed
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
    log_warning "cert-manager not found. Installing cert-manager..."
    "$SCRIPT_DIR/install-cert-manager.sh"
else
    log_info "cert-manager already installed, applying ClusterIssuer..."
    kubectl apply -f "$SCRIPT_DIR/07-cert-manager-issuer.yaml"
fi

log_info "Step 7: Creating SSL certificate..."
kubectl apply -f "$SCRIPT_DIR/08-ssl-certificate.yaml"

log_info "Step 8: Creating Ingress with SSL..."
kubectl apply -f "$SCRIPT_DIR/06-ingress.yaml"

# Wait for certificate to be ready
log_info "Waiting for SSL certificate to be issued..."
kubectl wait --for=condition=ready --timeout=300s certificate/ethos-ssl-cert -n "$NAMESPACE" || {
    log_warning "Certificate issuance may take a few minutes. Check status with: kubectl describe certificate ethos-ssl-cert -n $NAMESPACE"
}

echo ""
log_success "✅ WordPress deployment with SSL completed successfully!"

echo ""
log_info "📋 Deployment Summary:"
echo "- Namespace: $NAMESPACE"
echo "- MySQL: Deployed with persistent storage"
echo "- WordPress: Deployed with persistent storage"
echo "- SSL Certificate: Let's Encrypt certificate for ethos.gray-beard.com"
echo "- Ingress: Configured with SSL termination"

echo ""
log_info "🔍 Verification Commands:"
echo "kubectl get all -n $NAMESPACE"
echo "kubectl get pvc -n $NAMESPACE"
echo "kubectl get ingress -n $NAMESPACE"

echo ""
log_info "📊 Current Status:"
kubectl get pods -n "$NAMESPACE"

echo ""
log_info "🌐 Access Information:"
echo "- Local access: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
echo "- Then visit: http://localhost:8080"
echo "- Production access: https://ethos.gray-beard.com"
echo "- SSL Certificate: Automatically managed by cert-manager"

echo ""
log_info "📝 Next Steps:"
echo "1. Configure your DNS or /etc/hosts file to point wordpress.local to your ingress IP"
echo "2. Run the migration script to copy existing WordPress content: ./migrate-wordpress-content.sh"
echo "3. Access WordPress and complete the setup"

echo ""
log_warning "⚠️  Important Notes:"
echo "1. Update the secrets with secure passwords before production use"
echo "2. Configure proper SSL/TLS certificates for production"
echo "3. Consider setting up regular database backups"
