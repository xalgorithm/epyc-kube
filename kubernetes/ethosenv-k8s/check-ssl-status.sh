#!/bin/bash

# Check SSL Certificate Status
# This script checks the status of the SSL certificate for ethosenv.gray-beard.com

set -euo pipefail

NAMESPACE="ethosenv"
DOMAIN="ethos.gray-beard.com"

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

echo "🔐 SSL Certificate Status Check for $DOMAIN"
echo "============================================="

# Check if cert-manager is installed
log_info "Checking cert-manager installation..."
if kubectl get namespace cert-manager >/dev/null 2>&1; then
    if kubectl get pods -n cert-manager | grep -q "Running"; then
        log_success "cert-manager is running"
    else
        log_error "cert-manager pods are not running"
        kubectl get pods -n cert-manager
        exit 1
    fi
else
    log_error "cert-manager is not installed"
    exit 1
fi

# Check ClusterIssuer
log_info "Checking ClusterIssuer status..."
if kubectl get clusterissuer letsencrypt-prod >/dev/null 2>&1; then
    ISSUER_STATUS=$(kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    if [[ "$ISSUER_STATUS" == "True" ]]; then
        log_success "ClusterIssuer letsencrypt-prod is ready"
    else
        log_warning "ClusterIssuer status: $ISSUER_STATUS"
        kubectl describe clusterissuer letsencrypt-prod
    fi
else
    log_error "ClusterIssuer letsencrypt-prod not found"
    exit 1
fi

# Check Certificate
log_info "Checking Certificate status..."
if kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" >/dev/null 2>&1; then
    CERT_STATUS=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    CERT_REASON=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
    
    echo "Certificate Status: $CERT_STATUS"
    echo "Certificate Reason: $CERT_REASON"
    
    if [[ "$CERT_STATUS" == "True" ]]; then
        log_success "SSL Certificate is ready!"
        
        # Get certificate details
        CERT_EXPIRY=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.notAfter}' 2>/dev/null || echo "Unknown")
        echo "Certificate Expiry: $CERT_EXPIRY"
        
    elif [[ "$CERT_REASON" == "Issuing" ]]; then
        log_info "Certificate is being issued... This may take a few minutes."
    else
        log_warning "Certificate is not ready. Status: $CERT_STATUS, Reason: $CERT_REASON"
        echo ""
        log_info "Certificate details:"
        kubectl describe certificate ethos-ssl-cert -n "$NAMESPACE"
    fi
else
    log_error "Certificate ethos-ssl-cert not found in namespace $NAMESPACE"
    exit 1
fi

# Check TLS Secret
log_info "Checking TLS Secret..."
if kubectl get secret ethos-tls-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    SECRET_TYPE=$(kubectl get secret ethos-tls-secret -n "$NAMESPACE" -o jsonpath='{.type}')
    if [[ "$SECRET_TYPE" == "kubernetes.io/tls" ]]; then
        log_success "TLS Secret is present and valid"
        
        # Check certificate validity
        CERT_DATA=$(kubectl get secret ethos-tls-secret -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d)
        if echo "$CERT_DATA" | openssl x509 -noout -text >/dev/null 2>&1; then
            CERT_SUBJECT=$(echo "$CERT_DATA" | openssl x509 -noout -subject | sed 's/subject=//')
            CERT_ISSUER=$(echo "$CERT_DATA" | openssl x509 -noout -issuer | sed 's/issuer=//')
            CERT_DATES=$(echo "$CERT_DATA" | openssl x509 -noout -dates)
            
            echo "Certificate Subject: $CERT_SUBJECT"
            echo "Certificate Issuer: $CERT_ISSUER"
            echo "$CERT_DATES"
        else
            log_warning "Certificate data appears to be invalid"
        fi
    else
        log_warning "Secret type is $SECRET_TYPE, expected kubernetes.io/tls"
    fi
else
    log_warning "TLS Secret ethos-tls-secret not found"
fi

# Check Ingress
log_info "Checking Ingress configuration..."
if kubectl get ingress wordpress-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    INGRESS_TLS=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
    INGRESS_HOST=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
    
    if [[ "$INGRESS_TLS" == "ethos-tls-secret" ]]; then
        log_success "Ingress is configured with TLS secret"
    else
        log_warning "Ingress TLS configuration issue. Expected: ethos-tls-secret, Found: $INGRESS_TLS"
    fi
    
    if [[ "$INGRESS_HOST" == "$DOMAIN" ]]; then
        log_success "Ingress host is correctly configured: $INGRESS_HOST"
    else
        log_warning "Ingress host mismatch. Expected: $DOMAIN, Found: $INGRESS_HOST"
    fi
    
    # Get ingress IP
    INGRESS_IP=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$INGRESS_IP" ]]; then
        echo "Ingress IP: $INGRESS_IP"
    else
        log_warning "Ingress IP not yet assigned"
    fi
else
    log_error "Ingress wordpress-ingress not found"
fi

# Test SSL connection if possible
log_info "Testing SSL connection..."
if command -v openssl >/dev/null 2>&1; then
    if timeout 10 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null >/dev/null 2>&1; then
        log_success "SSL connection test passed"
        
        # Get certificate info from the actual connection
        LIVE_CERT_INFO=$(timeout 10 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "")
        if [[ -n "$LIVE_CERT_INFO" ]]; then
            echo "Live Certificate Info:"
            echo "$LIVE_CERT_INFO"
        fi
    else
        log_warning "SSL connection test failed. This is normal if DNS is not yet propagated or certificate is still being issued."
    fi
else
    log_info "openssl not available for connection testing"
fi

echo ""
log_info "🔍 Troubleshooting Commands:"
echo "kubectl describe certificate ethos-ssl-cert -n $NAMESPACE"
echo "kubectl describe secret ethos-tls-secret -n $NAMESPACE"
echo "kubectl describe ingress wordpress-ingress -n $NAMESPACE"
echo "kubectl logs -n cert-manager deployment/cert-manager"

echo ""
log_info "🌐 Access URLs:"
echo "HTTP: http://$DOMAIN (should redirect to HTTPS)"
echo "HTTPS: https://$DOMAIN"

echo ""
log_success "SSL certificate status check completed!"