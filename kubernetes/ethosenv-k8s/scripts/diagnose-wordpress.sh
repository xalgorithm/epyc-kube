#!/bin/bash

# Diagnose WordPress deployment and connectivity issues

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

echo "🔍 WordPress Deployment Diagnostics"
echo ""

# Check namespace
log_info "Checking namespace..."
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_success "✅ Namespace '$NAMESPACE' exists"
else
    log_error "❌ Namespace '$NAMESPACE' not found"
    exit 1
fi

# Check deployments
log_info "Checking deployments..."
echo "WordPress deployment:"
kubectl get deployment wordpress -n "$NAMESPACE" 2>/dev/null || log_error "WordPress deployment not found"

echo ""
echo "MySQL deployment:"
kubectl get deployment mysql -n "$NAMESPACE" 2>/dev/null || log_error "MySQL deployment not found"

# Check pods
echo ""
log_info "Checking pods..."
kubectl get pods -n "$NAMESPACE"

# Check pod status in detail
echo ""
log_info "Pod details:"
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$WORDPRESS_POD" ]; then
    echo "WordPress pod: $WORDPRESS_POD"
    kubectl describe pod "$WORDPRESS_POD" -n "$NAMESPACE" | grep -E "(Status|Ready|Conditions)" -A 5
else
    log_error "No WordPress pod found"
fi

if [ -n "$MYSQL_POD" ]; then
    echo ""
    echo "MySQL pod: $MYSQL_POD"
    kubectl describe pod "$MYSQL_POD" -n "$NAMESPACE" | grep -E "(Status|Ready|Conditions)" -A 5
else
    log_error "No MySQL pod found"
fi

# Check services
echo ""
log_info "Checking services..."
kubectl get services -n "$NAMESPACE"

# Check ingress
echo ""
log_info "Checking ingress..."
kubectl get ingress -n "$NAMESPACE" 2>/dev/null || log_warning "No ingress found"

if kubectl get ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    echo ""
    log_info "Ingress details:"
    kubectl describe ingress -n "$NAMESPACE"
fi

# Check endpoints
echo ""
log_info "Checking service endpoints..."
kubectl get endpoints -n "$NAMESPACE"

# Test internal connectivity
echo ""
log_info "Testing internal connectivity..."

if [ -n "$WORDPRESS_POD" ]; then
    log_info "Testing WordPress pod HTTP response..."
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ 2>/dev/null || log_warning "WordPress pod HTTP test failed"
fi

# Check WordPress service
log_info "Testing WordPress service..."
kubectl run test-pod --image=curlimages/curl --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}" http://wordpress.ethosenv.svc.cluster.local:80/ 2>/dev/null || log_warning "WordPress service test failed"

# Check DNS resolution
echo ""
log_info "Checking DNS resolution for ethos.gray-beard.com..."
nslookup ethos.gray-beard.com 2>/dev/null || log_warning "DNS resolution failed"

# Check SSL certificate
echo ""
log_info "Checking SSL certificate..."
kubectl get certificate -n "$NAMESPACE" 2>/dev/null || log_warning "No SSL certificates found"

if kubectl get certificate -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl describe certificate -n "$NAMESPACE"
fi

# Check cert-manager
echo ""
log_info "Checking cert-manager..."
kubectl get pods -n cert-manager 2>/dev/null || log_warning "cert-manager not found"

# Test external connectivity
echo ""
log_info "Testing external connectivity..."
curl -I https://ethos.gray-beard.com 2>/dev/null || log_error "External HTTPS test failed"

echo ""
log_success "🎉 Diagnostics completed!"

echo ""
log_info "📝 Common Issues and Solutions:"
echo "1. If pods are not ready: Check pod logs with 'kubectl logs <pod-name> -n $NAMESPACE'"
echo "2. If ingress shows no endpoints: Check service selectors and pod labels"
echo "3. If SSL certificate is not ready: Check cert-manager logs"
echo "4. If DNS fails: Verify domain configuration and DNS propagation"
echo "5. If external test fails: Check ingress controller and load balancer"

echo ""
log_info "🔧 Quick fixes:"
echo "# Check WordPress logs:"
echo "kubectl logs deployment/wordpress -n $NAMESPACE"
echo ""
echo "# Check MySQL logs:"
echo "kubectl logs deployment/mysql -n $NAMESPACE"
echo ""
echo "# Restart WordPress:"
echo "kubectl rollout restart deployment/wordpress -n $NAMESPACE"
echo ""
echo "# Port-forward for testing:"
echo "kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"