#!/bin/bash

# Quick check of ingress and service status

set -euo pipefail

NAMESPACE="ethosenv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "🔍 Quick Ingress & Service Check"
echo ""

# Check if WordPress service exists and has endpoints
log_info "WordPress Service Status:"
kubectl get service wordpress -n "$NAMESPACE" -o wide 2>/dev/null || log_error "WordPress service not found"

echo ""
log_info "WordPress Service Endpoints:"
kubectl get endpoints wordpress -n "$NAMESPACE" 2>/dev/null || log_error "WordPress endpoints not found"

# Check ingress
echo ""
log_info "WordPress Ingress Status:"
kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o wide 2>/dev/null || log_error "WordPress ingress not found"

# Check if pods are running and ready
echo ""
log_info "WordPress Pods:"
kubectl get pods -l app=wordpress -n "$NAMESPACE" -o wide 2>/dev/null || log_error "WordPress pods not found"

# Check Traefik ingress controller
echo ""
log_info "Traefik Ingress Controller:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik 2>/dev/null || log_warning "Traefik not found in kube-system"

# Test service directly
echo ""
log_info "Testing WordPress service directly:"
kubectl run test-curl --image=curlimages/curl --rm -i --restart=Never -- curl -s -I http://wordpress.ethosenv.svc.cluster.local:80/ 2>/dev/null || log_warning "Direct service test failed"

echo ""
log_success "Check completed!"

echo ""
log_info "🔧 If service has no endpoints:"
echo "1. Check if WordPress pods are running and ready"
echo "2. Verify service selector matches pod labels"
echo "3. Check if pods are listening on port 80"

echo ""
log_info "🔧 If ingress shows no address:"
echo "1. Check if ingress controller is running"
echo "2. Verify ingress class is correct"
echo "3. Check DNS configuration"

echo ""
log_info "🔧 Quick fixes:"
echo "# Restart WordPress deployment:"
echo "kubectl rollout restart deployment/wordpress -n $NAMESPACE"
echo ""
echo "# Delete and recreate ingress:"
echo "kubectl delete ingress wordpress-ingress -n $NAMESPACE"
echo "kubectl apply -f ../06-ingress.yaml"
echo ""
echo "# Test with port-forward:"
echo "kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"