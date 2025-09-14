#!/bin/bash

# Fix common WordPress ingress and connectivity issues

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

echo "🔧 WordPress Ingress & Connectivity Fixer"
echo ""

# Step 1: Check and restart WordPress deployment
log_info "1. Checking WordPress deployment..."
if kubectl get deployment wordpress -n "$NAMESPACE" >/dev/null 2>&1; then
    log_info "Restarting WordPress deployment..."
    kubectl rollout restart deployment/wordpress -n "$NAMESPACE"
    
    log_info "Waiting for WordPress to be ready..."
    kubectl rollout status deployment/wordpress -n "$NAMESPACE" --timeout=300s
    
    log_success "✅ WordPress deployment restarted"
else
    log_error "WordPress deployment not found. Please deploy WordPress first."
    exit 1
fi

# Step 2: Check service and endpoints
log_info "2. Checking WordPress service..."
kubectl get service wordpress -n "$NAMESPACE" -o wide

log_info "Checking service endpoints..."
ENDPOINTS=$(kubectl get endpoints wordpress -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")

if [ -z "$ENDPOINTS" ]; then
    log_warning "⚠️  No service endpoints found. This means pods are not ready or service selector is wrong."
    
    log_info "Checking pod labels..."
    kubectl get pods -l app=wordpress -n "$NAMESPACE" --show-labels
    
    log_info "Checking service selector..."
    kubectl get service wordpress -n "$NAMESPACE" -o jsonpath='{.spec.selector}'
    echo ""
else
    log_success "✅ Service has endpoints: $ENDPOINTS"
fi

# Step 3: Test service directly
log_info "3. Testing WordPress service directly..."
kubectl run test-service --image=curlimages/curl --rm -i --restart=Never -- curl -s -I http://wordpress.ethosenv.svc.cluster.local:80/ 2>/dev/null && log_success "✅ Service responds" || log_warning "⚠️  Service test failed"

# Step 4: Check and fix ingress
log_info "4. Checking ingress configuration..."
if kubectl get ingress wordpress-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    log_info "Current ingress status:"
    kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o wide
    
    # Check if ingress has an address
    INGRESS_ADDRESS=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -z "$INGRESS_ADDRESS" ]; then
        log_warning "⚠️  Ingress has no external address. Recreating ingress..."
        
        kubectl delete ingress wordpress-ingress -n "$NAMESPACE" 2>/dev/null || true
        sleep 5
        kubectl apply -f 06-ingress.yaml
        
        log_info "Waiting for ingress to get an address..."
        sleep 30
        kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o wide
    else
        log_success "✅ Ingress has address: $INGRESS_ADDRESS"
    fi
else
    log_warning "⚠️  Ingress not found. Creating ingress..."
    kubectl apply -f 06-ingress.yaml
fi

# Step 5: Check ingress controller
log_info "5. Checking Traefik ingress controller..."
if kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik >/dev/null 2>&1; then
    log_success "✅ Traefik ingress controller found"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
else
    log_warning "⚠️  Traefik ingress controller not found in kube-system"
    
    # Check other common namespaces
    for ns in traefik-system traefik default; do
        if kubectl get pods -n "$ns" -l app.kubernetes.io/name=traefik >/dev/null 2>&1; then
            log_info "Found Traefik in namespace: $ns"
            kubectl get pods -n "$ns" -l app.kubernetes.io/name=traefik
            break
        fi
    done
fi

# Step 6: Check SSL certificate
log_info "6. Checking SSL certificate..."
if kubectl get certificate ethos-tls-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    CERT_STATUS=$(kubectl get certificate ethos-tls-secret -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$CERT_STATUS" = "True" ]; then
        log_success "✅ SSL certificate is ready"
    else
        log_warning "⚠️  SSL certificate not ready. Status: $CERT_STATUS"
        kubectl describe certificate ethos-tls-secret -n "$NAMESPACE"
    fi
else
    log_warning "⚠️  SSL certificate not found"
fi

# Step 7: Test external connectivity
log_info "7. Testing external connectivity..."
echo "Testing HTTP (should redirect to HTTPS):"
curl -I http://ethos.xalg.im 2>/dev/null || log_warning "HTTP test failed"

echo ""
echo "Testing HTTPS:"
curl -I https://ethos.xalg.im 2>/dev/null || log_warning "HTTPS test failed"

# Step 8: DNS check
log_info "8. Checking DNS resolution..."
nslookup ethos.xalg.im 2>/dev/null || log_warning "DNS resolution failed"

echo ""
log_success "🎉 Ingress fix process completed!"

echo ""
log_info "📝 Summary of actions taken:"
echo "1. ✅ Restarted WordPress deployment"
echo "2. ✅ Checked service and endpoints"
echo "3. ✅ Tested internal service connectivity"
echo "4. ✅ Verified/recreated ingress configuration"
echo "5. ✅ Checked ingress controller status"
echo "6. ✅ Verified SSL certificate status"
echo "7. ✅ Tested external connectivity"
echo "8. ✅ Checked DNS resolution"

echo ""
log_info "🔍 If issues persist:"
echo "1. Check ingress controller logs: kubectl logs -n kube-system -l app.kubernetes.io/name=traefik"
echo "2. Check WordPress logs: kubectl logs deployment/wordpress -n $NAMESPACE"
echo "3. Test with port-forward: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
echo "4. Verify DNS propagation: dig ethos.xalg.im"

echo ""
log_info "🌐 Try accessing your site now:"
echo "https://ethos.xalg.im"
echo "https://ethos.xalg.im/wp-admin"