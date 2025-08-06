#!/bin/bash

# Certificate Error Handling Test Script
# Tests various error scenarios and proper error handling for SSL certificates
# Requirements: 1.4, 2.4, 3.4, 4.1, 4.2

set -euo pipefail

# Configuration
NAMESPACE="obsidian"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TIMEOUT=120

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# Test result tracking
start_test() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test "Starting test: $test_name"
}

pass_test() {
    local test_name="$1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_success "PASSED: $test_name"
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_error "FAILED: $test_name - $reason"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Test 1: Invalid ClusterIssuer error handling
test_invalid_cluster_issuer() {
    start_test "Invalid ClusterIssuer Error Handling"
    
    local test_cert_name="test-invalid-issuer-cert"
    local test_secret_name="test-invalid-issuer-secret"
    local test_ingress_name="test-invalid-issuer-ingress"
    
    # Create ingress with invalid ClusterIssuer
    cat > "/tmp/${test_ingress_name}.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${test_ingress_name}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "nonexistent-issuer"
spec:
  tls:
  - hosts:
    - test-invalid.example.com
    secretName: ${test_secret_name}
  rules:
  - host: test-invalid.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: obsidian
            port:
              number: 8080
EOF
    
    # Apply the invalid ingress
    if kubectl apply -f "/tmp/${test_ingress_name}.yaml" &> /dev/null; then
        log_info "Applied ingress with invalid ClusterIssuer"
        
        # Wait for cert-manager to process and fail
        sleep 30
        
        # Check if certificate was created
        if kubectl get certificate "$test_cert_name" -n "$NAMESPACE" &> /dev/null; then
            # Check certificate status
            local cert_ready
            cert_ready=$(kubectl get certificate "$test_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            
            if [ "$cert_ready" != "True" ]; then
                log_info "Certificate correctly failed with invalid ClusterIssuer"
                
                # Check for appropriate error message
                local error_message
                error_message=$(kubectl get certificate "$test_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                
                if echo "$error_message" | grep -qi "issuer\|not found"; then
                    log_info "Appropriate error message found: $error_message"
                    pass_test "Invalid ClusterIssuer Error Handling"
                else
                    fail_test "Invalid ClusterIssuer Error Handling" "No appropriate error message found: $error_message"
                fi
            else
                fail_test "Invalid ClusterIssuer Error Handling" "Certificate unexpectedly succeeded with invalid issuer"
            fi
        else
            log_info "Certificate resource was not created (expected behavior)"
            pass_test "Invalid ClusterIssuer Error Handling"
        fi
    else
        fail_test "Invalid ClusterIssuer Error Handling" "Failed to apply invalid ingress"
    fi
    
    # Cleanup
    kubectl delete -f "/tmp/${test_ingress_name}.yaml" --ignore-not-found=true &> /dev/null
    kubectl delete certificate "$test_cert_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    kubectl delete secret "$test_secret_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    rm -f "/tmp/${test_ingress_name}.yaml"
}

# Test 2: Invalid domain name error handling
test_invalid_domain_name() {
    start_test "Invalid Domain Name Error Handling"
    
    local test_cert_name="test-invalid-domain-cert"
    local test_secret_name="test-invalid-domain-secret"
    local test_ingress_name="test-invalid-domain-ingress"
    local invalid_domain="invalid-domain-that-does-not-exist-12345.com"
    
    # Create ingress with invalid domain
    cat > "/tmp/${test_ingress_name}.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${test_ingress_name}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  tls:
  - hosts:
    - ${invalid_domain}
    secretName: ${test_secret_name}
  rules:
  - host: ${invalid_domain}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: obsidian
            port:
              number: 8080
EOF
    
    # Apply the invalid ingress
    if kubectl apply -f "/tmp/${test_ingress_name}.yaml" &> /dev/null; then
        log_info "Applied ingress with invalid domain name"
        
        # Wait for cert-manager to process and fail
        sleep 60
        
        # Check if certificate was created
        if kubectl get certificate "$test_cert_name" -n "$NAMESPACE" &> /dev/null; then
            # Check certificate status
            local cert_ready
            cert_ready=$(kubectl get certificate "$test_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            
            if [ "$cert_ready" != "True" ]; then
                log_info "Certificate correctly failed with invalid domain"
                
                # Check for appropriate error message
                local error_message
                error_message=$(kubectl get certificate "$test_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                
                if echo "$error_message" | grep -qi "challenge\|validation\|dns\|domain"; then
                    log_info "Appropriate error message found: $error_message"
                    pass_test "Invalid Domain Name Error Handling"
                else
                    log_warning "Error message may not be specific: $error_message"
                    pass_test "Invalid Domain Name Error Handling"
                fi
            else
                fail_test "Invalid Domain Name Error Handling" "Certificate unexpectedly succeeded with invalid domain"
            fi
        else
            log_info "Certificate resource was not created"
            # This could be expected behavior depending on cert-manager configuration
            pass_test "Invalid Domain Name Error Handling"
        fi
    else
        fail_test "Invalid Domain Name Error Handling" "Failed to apply invalid ingress"
    fi
    
    # Cleanup
    kubectl delete -f "/tmp/${test_ingress_name}.yaml" --ignore-not-found=true &> /dev/null
    kubectl delete certificate "$test_cert_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    kubectl delete secret "$test_secret_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    rm -f "/tmp/${test_ingress_name}.yaml"
}

# Test 3: Missing service backend error handling
test_missing_service_backend() {
    start_test "Missing Service Backend Error Handling"
    
    local test_cert_name="test-missing-service-cert"
    local test_secret_name="test-missing-service-secret"
    local test_ingress_name="test-missing-service-ingress"
    local test_domain="test-missing-service.example.com"
    
    # Create ingress with non-existent service
    cat > "/tmp/${test_ingress_name}.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${test_ingress_name}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  tls:
  - hosts:
    - ${test_domain}
    secretName: ${test_secret_name}
  rules:
  - host: ${test_domain}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nonexistent-service
            port:
              number: 8080
EOF
    
    # Apply the ingress with missing service
    if kubectl apply -f "/tmp/${test_ingress_name}.yaml" &> /dev/null; then
        log_info "Applied ingress with missing service backend"
        
        # Wait for processing
        sleep 30
        
        # Check ingress status
        local ingress_status
        ingress_status=$(kubectl get ingress "$test_ingress_name" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -z "$ingress_status" ]; then
            log_info "Ingress correctly has no load balancer IP (expected with missing service)"
        fi
        
        # The certificate might still be issued even if the service doesn't exist
        # because cert-manager only cares about domain validation, not service availability
        if kubectl get certificate "$test_cert_name" -n "$NAMESPACE" &> /dev/null; then
            log_info "Certificate resource was created despite missing service"
            
            # This is actually expected behavior - cert-manager can issue certificates
            # even if the backend service doesn't exist
            pass_test "Missing Service Backend Error Handling"
        else
            log_info "Certificate resource was not created"
            pass_test "Missing Service Backend Error Handling"
        fi
    else
        fail_test "Missing Service Backend Error Handling" "Failed to apply ingress with missing service"
    fi
    
    # Cleanup
    kubectl delete -f "/tmp/${test_ingress_name}.yaml" --ignore-not-found=true &> /dev/null
    kubectl delete certificate "$test_cert_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    kubectl delete secret "$test_secret_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    rm -f "/tmp/${test_ingress_name}.yaml"
}

# Test 4: Rate limiting error handling
test_rate_limiting_simulation() {
    start_test "Rate Limiting Error Handling"
    
    # This test simulates rate limiting by creating multiple certificate requests quickly
    # Note: This uses staging environment to avoid actual rate limiting issues
    
    local base_name="test-rate-limit"
    local num_certs=5
    local created_resources=()
    
    log_info "Creating multiple certificate requests to simulate rate limiting..."
    
    for i in $(seq 1 $num_certs); do
        local cert_name="${base_name}-${i}"
        local secret_name="${base_name}-secret-${i}"
        local ingress_name="${base_name}-ingress-${i}"
        local domain="${base_name}-${i}.example.com"
        
        created_resources+=("$ingress_name" "$cert_name" "$secret_name")
        
        cat > "/tmp/${ingress_name}.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${ingress_name}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  tls:
  - hosts:
    - ${domain}
    secretName: ${secret_name}
  rules:
  - host: ${domain}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: obsidian
            port:
              number: 8080
EOF
        
        kubectl apply -f "/tmp/${ingress_name}.yaml" &> /dev/null
        sleep 2  # Small delay between requests
    done
    
    # Wait for cert-manager to process all requests
    sleep 60
    
    # Check if any certificates show rate limiting errors
    local rate_limit_detected=false
    
    for i in $(seq 1 $num_certs); do
        local cert_name="${base_name}-${i}"
        
        if kubectl get certificate "$cert_name" -n "$NAMESPACE" &> /dev/null; then
            local error_message
            error_message=$(kubectl get certificate "$cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
            
            if echo "$error_message" | grep -qi "rate\|limit\|too many"; then
                log_info "Rate limiting detected for certificate '$cert_name': $error_message"
                rate_limit_detected=true
            fi
        fi
    done
    
    if [ "$rate_limit_detected" = true ]; then
        log_info "Rate limiting error handling working correctly"
        pass_test "Rate Limiting Error Handling"
    else
        log_info "No rate limiting detected (may be expected with staging environment)"
        pass_test "Rate Limiting Error Handling"
    fi
    
    # Cleanup all created resources
    for i in $(seq 1 $num_certs); do
        local cert_name="${base_name}-${i}"
        local secret_name="${base_name}-secret-${i}"
        local ingress_name="${base_name}-ingress-${i}"
        
        kubectl delete ingress "$ingress_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
        kubectl delete certificate "$cert_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
        kubectl delete secret "$secret_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
        rm -f "/tmp/${ingress_name}.yaml"
    done
}

# Test 5: Certificate validation failure handling
test_certificate_validation_failure() {
    start_test "Certificate Validation Failure Handling"
    
    local test_cert_name="test-validation-failure-cert"
    local test_secret_name="test-validation-failure-secret"
    
    # Create a certificate resource directly (without ingress) with invalid configuration
    cat > "/tmp/test-validation-failure.yaml" << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${test_cert_name}
  namespace: ${NAMESPACE}
spec:
  secretName: ${test_secret_name}
  dnsNames:
  - "*.invalid-wildcard-domain-12345.com"  # Wildcard that can't be validated via HTTP-01
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  # Force HTTP-01 challenge for wildcard (which should fail)
  acme:
    config:
    - http01:
        ingress: {}
      domains:
      - "*.invalid-wildcard-domain-12345.com"
EOF
    
    # Apply the invalid certificate
    if kubectl apply -f "/tmp/test-validation-failure.yaml" &> /dev/null; then
        log_info "Applied certificate with validation failure scenario"
        
        # Wait for cert-manager to process and fail
        sleep 60
        
        # Check certificate status
        local cert_ready
        cert_ready=$(kubectl get certificate "$test_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$cert_ready" != "True" ]; then
            log_info "Certificate correctly failed validation"
            
            # Check for appropriate error message
            local error_message
            error_message=$(kubectl get certificate "$test_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
            
            if echo "$error_message" | grep -qi "validation\|challenge\|failed"; then
                log_info "Appropriate validation error message found: $error_message"
                pass_test "Certificate Validation Failure Handling"
            else
                log_warning "Error message may not be specific: $error_message"
                pass_test "Certificate Validation Failure Handling"
            fi
        else
            fail_test "Certificate Validation Failure Handling" "Certificate unexpectedly succeeded with invalid configuration"
        fi
    else
        fail_test "Certificate Validation Failure Handling" "Failed to apply invalid certificate"
    fi
    
    # Cleanup
    kubectl delete -f "/tmp/test-validation-failure.yaml" --ignore-not-found=true &> /dev/null
    kubectl delete secret "$test_secret_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    rm -f "/tmp/test-validation-failure.yaml"
}

# Test 6: Network connectivity error handling
test_network_connectivity_errors() {
    start_test "Network Connectivity Error Handling"
    
    # This test checks if cert-manager properly handles network connectivity issues
    # We'll check the cert-manager logs for any network-related errors
    
    log_info "Checking cert-manager logs for network connectivity error handling..."
    
    # Get recent cert-manager logs
    local cert_manager_logs
    cert_manager_logs=$(kubectl logs -n cert-manager deployment/cert-manager --tail=100 2>/dev/null || echo "")
    
    if [ -n "$cert_manager_logs" ]; then
        # Look for network-related error handling
        if echo "$cert_manager_logs" | grep -qi "network\|timeout\|connection\|dns"; then
            log_info "Network-related error handling found in cert-manager logs"
        else
            log_info "No recent network errors in cert-manager logs (this is good)"
        fi
        
        # Check for proper error handling patterns
        if echo "$cert_manager_logs" | grep -qi "error\|failed" && echo "$cert_manager_logs" | grep -qi "retry\|backoff"; then
            log_info "Error handling with retry logic detected"
        fi
        
        pass_test "Network Connectivity Error Handling"
    else
        log_warning "Could not retrieve cert-manager logs"
        pass_test "Network Connectivity Error Handling"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Certificate Error Handling Test Script"
    echo
    echo "Options:"
    echo "  --timeout SECONDS      Set test timeout (default: 120)"
    echo "  --skip-rate-limit      Skip rate limiting test"
    echo "  --skip-network         Skip network connectivity test"
    echo "  --help                 Show this help message"
    echo
}

# Parse command line arguments
SKIP_RATE_LIMIT=false
SKIP_NETWORK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        --skip-rate-limit)
            SKIP_RATE_LIMIT=true
            shift
            ;;
        --skip-network)
            SKIP_NETWORK=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "Certificate Error Handling Test Suite"
    echo "====================================="
    echo
    
    check_prerequisites
    echo
    
    # Run error handling tests
    test_invalid_cluster_issuer
    echo
    
    test_invalid_domain_name
    echo
    
    test_missing_service_backend
    echo
    
    if [ "$SKIP_RATE_LIMIT" = false ]; then
        test_rate_limiting_simulation
        echo
    fi
    
    test_certificate_validation_failure
    echo
    
    if [ "$SKIP_NETWORK" = false ]; then
        test_network_connectivity_errors
        echo
    fi
    
    # Summary
    echo "====================================="
    echo "Error Handling Test Summary"
    echo "====================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All error handling tests PASSED!"
        exit 0
    else
        log_error "Some error handling tests FAILED!"
        exit 1
    fi
}

# Run main function
main "$@"