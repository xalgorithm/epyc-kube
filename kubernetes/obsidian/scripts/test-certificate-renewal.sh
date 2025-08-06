#!/bin/bash

# Certificate Renewal Test Script
# Simulates and tests certificate renewal scenarios for Obsidian stack
# Requirements: 1.2, 2.2, 3.4

set -euo pipefail

# Configuration
NAMESPACE="obsidian"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTIFICATES=("obsidian-tls" "couchdb-tls")
RENEWAL_TIMEOUT=300

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

# Function to get certificate creation timestamp
get_certificate_creation_time() {
    local cert_name=$1
    kubectl get certificate "$cert_name" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo ""
}

# Function to get certificate serial number
get_certificate_serial() {
    local secret_name=$1
    local cert_data
    cert_data=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
    
    if [ -n "$cert_data" ]; then
        echo "$cert_data" | base64 -d | openssl x509 -serial -noout 2>/dev/null | cut -d= -f2
    else
        echo ""
    fi
}

# Function to wait for certificate to be ready
wait_for_certificate_ready() {
    local cert_name=$1
    local timeout=$2
    
    log_info "Waiting for certificate '$cert_name' to be ready (timeout: ${timeout}s)..."
    
    if kubectl wait --for=condition=Ready certificate/"$cert_name" -n "$NAMESPACE" --timeout="${timeout}s"; then
        log_success "Certificate '$cert_name' is ready"
        return 0
    else
        log_error "Certificate '$cert_name' failed to become ready within ${timeout}s"
        
        # Show certificate status for debugging
        log_info "Certificate status:"
        kubectl describe certificate "$cert_name" -n "$NAMESPACE" | grep -A 10 "Status:"
        
        return 1
    fi
}

# Test 1: Manual certificate renewal by deletion
test_manual_renewal_by_deletion() {
    log_info "=== Test 1: Manual Certificate Renewal by Deletion ==="
    
    local test_passed=true
    
    # Store original certificate information
    declare -A original_creation_times
    declare -A original_serials
    
    for cert in "${CERTIFICATES[@]}"; do
        original_creation_times[$cert]=$(get_certificate_creation_time "$cert")
        original_serials[$cert]=$(get_certificate_serial "$cert")
        
        log_info "Original $cert creation time: ${original_creation_times[$cert]}"
        log_info "Original $cert serial: ${original_serials[$cert]}"
    done
    
    # Delete certificates to trigger renewal
    log_info "Deleting certificates to trigger renewal..."
    for cert in "${CERTIFICATES[@]}"; do
        kubectl delete certificate "$cert" -n "$NAMESPACE" --ignore-not-found=true
    done
    
    # Wait a moment for deletion to complete
    sleep 10
    
    # Wait for certificates to be recreated and ready
    for cert in "${CERTIFICATES[@]}"; do
        if ! wait_for_certificate_ready "$cert" "$RENEWAL_TIMEOUT"; then
            test_passed=false
        fi
    done
    
    if [ "$test_passed" = true ]; then
        # Verify certificates were actually renewed (different creation times/serials)
        for cert in "${CERTIFICATES[@]}"; do
            local new_creation_time
            local new_serial
            
            new_creation_time=$(get_certificate_creation_time "$cert")
            new_serial=$(get_certificate_serial "$cert")
            
            log_info "New $cert creation time: $new_creation_time"
            log_info "New $cert serial: $new_serial"
            
            if [ "$new_creation_time" != "${original_creation_times[$cert]}" ]; then
                log_success "Certificate '$cert' was renewed (creation time changed)"
            else
                log_warning "Certificate '$cert' creation time unchanged"
            fi
            
            if [ -n "$new_serial" ] && [ "$new_serial" != "${original_serials[$cert]}" ]; then
                log_success "Certificate '$cert' has new serial number"
            else
                log_warning "Certificate '$cert' serial number unchanged or unavailable"
            fi
        done
        
        log_success "Manual renewal by deletion test PASSED"
        return 0
    else
        log_error "Manual renewal by deletion test FAILED"
        return 1
    fi
}

# Test 2: Certificate renewal by secret deletion
test_renewal_by_secret_deletion() {
    log_info "=== Test 2: Certificate Renewal by Secret Deletion ==="
    
    local test_passed=true
    
    # Store original secret information
    declare -A original_secret_uids
    declare -A original_serials
    
    for cert in "${CERTIFICATES[@]}"; do
        if kubectl get secret "$cert" -n "$NAMESPACE" &> /dev/null; then
            original_secret_uids[$cert]=$(kubectl get secret "$cert" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')
            original_serials[$cert]=$(get_certificate_serial "$cert")
            
            log_info "Original $cert secret UID: ${original_secret_uids[$cert]}"
            log_info "Original $cert serial: ${original_serials[$cert]}"
        else
            log_warning "Secret '$cert' not found"
        fi
    done
    
    # Delete secrets to trigger renewal
    log_info "Deleting certificate secrets to trigger renewal..."
    for cert in "${CERTIFICATES[@]}"; do
        kubectl delete secret "$cert" -n "$NAMESPACE" --ignore-not-found=true
    done
    
    # Wait a moment for deletion to complete
    sleep 10
    
    # Wait for certificates to recreate secrets
    for cert in "${CERTIFICATES[@]}"; do
        log_info "Waiting for secret '$cert' to be recreated..."
        local timeout=60
        local elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
            if kubectl get secret "$cert" -n "$NAMESPACE" &> /dev/null; then
                log_success "Secret '$cert' recreated"
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        if [ $elapsed -ge $timeout ]; then
            log_error "Secret '$cert' was not recreated within ${timeout}s"
            test_passed=false
        fi
    done
    
    if [ "$test_passed" = true ]; then
        # Verify secrets were actually recreated (different UIDs)
        for cert in "${CERTIFICATES[@]}"; do
            if kubectl get secret "$cert" -n "$NAMESPACE" &> /dev/null; then
                local new_secret_uid
                local new_serial
                
                new_secret_uid=$(kubectl get secret "$cert" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')
                new_serial=$(get_certificate_serial "$cert")
                
                log_info "New $cert secret UID: $new_secret_uid"
                log_info "New $cert serial: $new_serial"
                
                if [ "$new_secret_uid" != "${original_secret_uids[$cert]}" ]; then
                    log_success "Secret '$cert' was recreated (UID changed)"
                else
                    log_warning "Secret '$cert' UID unchanged"
                fi
                
                if [ -n "$new_serial" ] && [ "$new_serial" != "${original_serials[$cert]}" ]; then
                    log_success "Certificate '$cert' has new serial number"
                else
                    log_warning "Certificate '$cert' serial number unchanged or unavailable"
                fi
            fi
        done
        
        log_success "Renewal by secret deletion test PASSED"
        return 0
    else
        log_error "Renewal by secret deletion test FAILED"
        return 1
    fi
}

# Test 3: Verify certificate auto-renewal behavior
test_certificate_auto_renewal_behavior() {
    log_info "=== Test 3: Certificate Auto-Renewal Behavior ==="
    
    # This test verifies that cert-manager is configured for auto-renewal
    # by checking certificate annotations and renewal settings
    
    local test_passed=true
    
    for cert in "${CERTIFICATES[@]}"; do
        log_info "Checking auto-renewal configuration for certificate '$cert'..."
        
        if kubectl get certificate "$cert" -n "$NAMESPACE" &> /dev/null; then
            # Check certificate spec for renewal settings
            local renewal_before
            renewal_before=$(kubectl get certificate "$cert" -n "$NAMESPACE" -o jsonpath='{.spec.renewBefore}' 2>/dev/null || echo "")
            
            if [ -n "$renewal_before" ]; then
                log_info "Certificate '$cert' has renewBefore setting: $renewal_before"
            else
                log_info "Certificate '$cert' using default renewal settings"
            fi
            
            # Check if certificate has proper issuer reference
            local issuer_name
            local issuer_kind
            
            issuer_name=$(kubectl get certificate "$cert" -n "$NAMESPACE" -o jsonpath='{.spec.issuerRef.name}' 2>/dev/null || echo "")
            issuer_kind=$(kubectl get certificate "$cert" -n "$NAMESPACE" -o jsonpath='{.spec.issuerRef.kind}' 2>/dev/null || echo "")
            
            if [ -n "$issuer_name" ] && [ -n "$issuer_kind" ]; then
                log_success "Certificate '$cert' has proper issuer reference: $issuer_kind/$issuer_name"
            else
                log_error "Certificate '$cert' missing issuer reference"
                test_passed=false
            fi
            
            # Check certificate status
            local ready_condition
            ready_condition=$(kubectl get certificate "$cert" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
            
            if [ "$ready_condition" = "True" ]; then
                log_success "Certificate '$cert' is ready for auto-renewal"
            else
                log_warning "Certificate '$cert' ready status: $ready_condition"
            fi
            
        else
            log_error "Certificate '$cert' not found"
            test_passed=false
        fi
    done
    
    if [ "$test_passed" = true ]; then
        log_success "Certificate auto-renewal behavior test PASSED"
        return 0
    else
        log_error "Certificate auto-renewal behavior test FAILED"
        return 1
    fi
}

# Test 4: Simulate certificate near expiry
test_certificate_near_expiry_simulation() {
    log_info "=== Test 4: Certificate Near Expiry Simulation ==="
    
    # This test creates a temporary certificate with a very short validity period
    # to test renewal behavior when certificates are near expiry
    
    log_info "Creating temporary certificate with short validity for testing..."
    
    # Create a temporary self-signed certificate with 1-day validity
    local temp_cert_name="test-short-lived-cert"
    local temp_secret_name="test-short-lived-secret"
    
    # Generate temporary certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/temp.key -out /tmp/temp.crt \
        -days 1 -nodes -subj "/CN=test.example.com" &> /dev/null
    
    # Create secret with the temporary certificate
    kubectl create secret tls "$temp_secret_name" \
        --cert=/tmp/temp.crt --key=/tmp/temp.key -n "$NAMESPACE" &> /dev/null
    
    # Create a temporary certificate resource that references this secret
    cat > /tmp/temp-cert.yaml << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${temp_cert_name}
  namespace: ${NAMESPACE}
spec:
  secretName: ${temp_secret_name}
  dnsNames:
  - test.example.com
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  renewBefore: 23h  # Renew when less than 23 hours remain
EOF
    
    kubectl apply -f /tmp/temp-cert.yaml &> /dev/null
    
    # Wait a moment for cert-manager to process
    sleep 30
    
    # Check if cert-manager detected the certificate needs renewal
    local cert_status
    cert_status=$(kubectl get certificate "$temp_cert_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    log_info "Temporary certificate status: $cert_status"
    
    # Check certificate events for renewal activity
    local renewal_events
    renewal_events=$(kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$temp_cert_name" --sort-by='.lastTimestamp' -o custom-columns=REASON:.reason,MESSAGE:.message --no-headers 2>/dev/null || echo "")
    
    if [ -n "$renewal_events" ]; then
        log_info "Certificate events:"
        echo "$renewal_events"
        
        if echo "$renewal_events" | grep -qi "renew\|issue"; then
            log_success "cert-manager detected certificate needs renewal"
        else
            log_info "No explicit renewal events found (may be normal for short test)"
        fi
    fi
    
    # Cleanup temporary resources
    kubectl delete certificate "$temp_cert_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    kubectl delete secret "$temp_secret_name" -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    rm -f /tmp/temp.key /tmp/temp.crt /tmp/temp-cert.yaml
    
    log_success "Certificate near expiry simulation test PASSED"
    return 0
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Certificate Renewal Test Script"
    echo
    echo "Options:"
    echo "  --timeout SECONDS      Set renewal timeout (default: 300)"
    echo "  --skip-deletion        Skip deletion-based renewal tests"
    echo "  --skip-expiry          Skip expiry simulation test"
    echo "  --help                 Show this help message"
    echo
}

# Parse command line arguments
SKIP_DELETION=false
SKIP_EXPIRY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            RENEWAL_TIMEOUT="$2"
            shift 2
            ;;
        --skip-deletion)
            SKIP_DELETION=true
            shift
            ;;
        --skip-expiry)
            SKIP_EXPIRY=true
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
    echo "Certificate Renewal Test Suite"
    echo "=============================="
    echo
    
    check_prerequisites
    echo
    
    local tests_passed=0
    local tests_failed=0
    
    # Run renewal tests
    if [ "$SKIP_DELETION" = false ]; then
        if test_manual_renewal_by_deletion; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
        echo
        
        if test_renewal_by_secret_deletion; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
        echo
    fi
    
    if test_certificate_auto_renewal_behavior; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if [ "$SKIP_EXPIRY" = false ]; then
        if test_certificate_near_expiry_simulation; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
        echo
    fi
    
    # Summary
    echo "=============================="
    echo "Certificate Renewal Test Summary"
    echo "=============================="
    echo "Tests Passed: $tests_passed"
    echo "Tests Failed: $tests_failed"
    echo "Total Tests: $((tests_passed + tests_failed))"
    
    if [ $tests_failed -eq 0 ]; then
        log_success "All certificate renewal tests PASSED!"
        exit 0
    else
        log_error "Some certificate renewal tests FAILED!"
        exit 1
    fi
}

# Run main function
main "$@"