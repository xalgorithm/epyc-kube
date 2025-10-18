#!/bin/bash

# Test Airflow Ingress and TLS Configuration
# This script validates the implementation of task 7
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

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "✓ $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

log_info "Starting Airflow Ingress and TLS validation tests..."
log_info "=================================================="

# Test 1: Check if ClusterIssuer exists
run_test "ClusterIssuer exists" \
    "kubectl get clusterissuer letsencrypt-prod &> /dev/null"

# Test 2: Check if Certificate resource exists
run_test "Certificate resource exists" \
    "kubectl get certificate airflow-tls-certificate -n airflow &> /dev/null"

# Test 3: Check if Ingress exists
run_test "Ingress resource exists" \
    "kubectl get ingress airflow-tls -n airflow &> /dev/null"

# Test 4: Check if TLS secret exists
run_test "TLS secret exists" \
    "kubectl get secret airflow-tls-secret -n airflow &> /dev/null"

# Test 5: Check if security headers middleware exists
run_test "Security headers middleware exists" \
    "kubectl get middleware security-headers -n airflow &> /dev/null"

# Test 6: Check if rate limiting middleware exists
run_test "Rate limiting middleware exists" \
    "kubectl get middleware rate-limit -n airflow &> /dev/null"

# Test 7: Check if HTTP redirect middleware exists
run_test "HTTP redirect middleware exists" \
    "kubectl get middleware redirect-https -n kube-system &> /dev/null"

# Test 8: Validate certificate status
log_info "Checking certificate status..."
CERT_STATUS=$(kubectl get certificate airflow-tls-certificate -n airflow -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$CERT_STATUS" = "True" ]; then
    log_success "✓ Certificate is ready and valid"
    ((TESTS_PASSED++))
elif [ "$CERT_STATUS" = "False" ]; then
    log_warning "⚠ Certificate is not ready yet"
    kubectl describe certificate airflow-tls-certificate -n airflow | grep -A 10 "Status:"
    ((TESTS_FAILED++))
else
    log_error "✗ Cannot determine certificate status"
    ((TESTS_FAILED++))
fi

# Test 9: Validate ingress configuration
log_info "Validating ingress configuration..."
INGRESS_HOST=$(kubectl get ingress airflow-tls -n airflow -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

if [ "$INGRESS_HOST" = "airflow.gray-beard.com" ]; then
    log_success "✓ Ingress host configured correctly"
    ((TESTS_PASSED++))
else
    log_error "✗ Ingress host misconfigured. Expected: airflow.gray-beard.com, Got: $INGRESS_HOST"
    ((TESTS_FAILED++))
fi

# Test 10: Check TLS configuration in ingress
TLS_HOST=$(kubectl get ingress airflow-tls -n airflow -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null || echo "")

if [ "$TLS_HOST" = "airflow.gray-beard.com" ]; then
    log_success "✓ TLS configuration correct in ingress"
    ((TESTS_PASSED++))
else
    log_error "✗ TLS configuration incorrect. Expected: airflow.gray-beard.com, Got: $TLS_HOST"
    ((TESTS_FAILED++))
fi

# Test 11: Validate security annotations
log_info "Validating security annotations..."
SECURITY_ANNOTATIONS=$(kubectl get ingress airflow-tls -n airflow -o jsonpath='{.metadata.annotations}' 2>/dev/null || echo "{}")

if echo "$SECURITY_ANNOTATIONS" | grep -q "traefik.ingress.kubernetes.io/router.tls"; then
    log_success "✓ TLS enforcement annotation present"
    ((TESTS_PASSED++))
else
    log_error "✗ TLS enforcement annotation missing"
    ((TESTS_FAILED++))
fi

if echo "$SECURITY_ANNOTATIONS" | grep -q "cert-manager.io/cluster-issuer"; then
    log_success "✓ cert-manager annotation present"
    ((TESTS_PASSED++))
else
    log_error "✗ cert-manager annotation missing"
    ((TESTS_FAILED++))
fi

# Test 12: Check middleware configuration
log_info "Validating middleware configuration..."
SECURITY_HEADERS_CONFIG=$(kubectl get middleware security-headers -n airflow -o jsonpath='{.spec.headers.customResponseHeaders}' 2>/dev/null || echo "{}")

if echo "$SECURITY_HEADERS_CONFIG" | grep -q "X-Frame-Options"; then
    log_success "✓ Security headers configured"
    ((TESTS_PASSED++))
else
    log_error "✗ Security headers not configured properly"
    ((TESTS_FAILED++))
fi

RATE_LIMIT_CONFIG=$(kubectl get middleware rate-limit -n airflow -o jsonpath='{.spec.rateLimit.average}' 2>/dev/null || echo "0")

if [ "$RATE_LIMIT_CONFIG" = "100" ]; then
    log_success "✓ Rate limiting configured correctly (100 req/min)"
    ((TESTS_PASSED++))
else
    log_error "✗ Rate limiting not configured correctly. Expected: 100, Got: $RATE_LIMIT_CONFIG"
    ((TESTS_FAILED++))
fi

# Test 13: Network connectivity test (if possible)
log_info "Testing network connectivity..."
if command -v curl &> /dev/null; then
    # Test HTTP redirect (should redirect to HTTPS)
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "http://airflow.gray-beard.com" 2>/dev/null || echo "000")
    
    if [ "$HTTP_RESPONSE" = "200" ] || [ "$HTTP_RESPONSE" = "301" ] || [ "$HTTP_RESPONSE" = "302" ]; then
        log_success "✓ HTTP connectivity working (response: $HTTP_RESPONSE)"
        ((TESTS_PASSED++))
    else
        log_warning "⚠ HTTP connectivity test failed (response: $HTTP_RESPONSE) - DNS may not be configured yet"
        ((TESTS_FAILED++))
    fi
    
    # Test HTTPS connectivity
    HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "https://airflow.gray-beard.com" 2>/dev/null || echo "000")
    
    if [ "$HTTPS_RESPONSE" = "200" ] || [ "$HTTPS_RESPONSE" = "401" ] || [ "$HTTPS_RESPONSE" = "403" ]; then
        log_success "✓ HTTPS connectivity working (response: $HTTPS_RESPONSE)"
        ((TESTS_PASSED++))
    else
        log_warning "⚠ HTTPS connectivity test failed (response: $HTTPS_RESPONSE) - DNS or certificate may not be ready"
        ((TESTS_FAILED++))
    fi
else
    log_warning "⚠ curl not available, skipping connectivity tests"
    ((TESTS_FAILED += 2))
fi

# Summary
log_info ""
log_info "Test Summary"
log_info "============"
log_info "Tests passed: $TESTS_PASSED"
log_info "Tests failed: $TESTS_FAILED"
log_info "Total tests: $((TESTS_PASSED + TESTS_FAILED))"

if [ $TESTS_FAILED -eq 0 ]; then
    log_success "All tests passed! Airflow Ingress and TLS configuration is working correctly."
    exit 0
elif [ $TESTS_FAILED -le 2 ]; then
    log_warning "Most tests passed with minor issues. Configuration is mostly working."
    log_info "Common issues:"
    log_info "- Certificate may still be pending issuance"
    log_info "- DNS may not be configured yet"
    log_info "- Airflow service may not be running yet"
    exit 0
else
    log_error "Multiple tests failed. Please review the configuration."
    exit 1
fi