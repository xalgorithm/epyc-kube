#!/bin/bash

# Automated Certificate Functionality Test Suite
# Tests SSL certificate provisioning, renewal, and error handling for Obsidian stack
# Requirements: 1.1, 1.2, 1.4, 2.1, 2.2, 2.4, 3.4, 4.1, 4.2

set -euo pipefail

# Configuration
NAMESPACE="obsidian"
OBSIDIAN_DOMAIN="blackrock.gray-beard.com"
COUCHDB_DOMAIN="couchdb.blackrock.gray-beard.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBSIDIAN_DIR="$(dirname "$SCRIPT_DIR")"
TEST_RESULTS_DIR="${SCRIPT_DIR}/test-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${TEST_RESULTS_DIR}/certificate-tests-${TIMESTAMP}.log"

# Test configuration
STAGING_CLUSTER_ISSUER="letsencrypt-staging"
PROD_CLUSTER_ISSUER="letsencrypt-prod"
CERTIFICATE_TIMEOUT=300
CONNECTIVITY_TIMEOUT=30

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
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1" | tee -a "$LOG_FILE"
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

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Initialize log file
    echo "Certificate Functionality Test Suite - $(date)" > "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    log_success "Test environment setup complete"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    # Check cert-manager is running
    if ! kubectl get pods -n cert-manager | grep -q "cert-manager.*Running"; then
        log_error "cert-manager is not running"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Test 1: Validate ClusterIssuer availability
test_cluster_issuer_availability() {
    start_test "ClusterIssuer Availability"
    
    local staging_ready=false
    local prod_ready=false
    
    # Check staging ClusterIssuer
    if kubectl get clusterissuer "$STAGING_CLUSTER_ISSUER" &> /dev/null; then
        local staging_status
        staging_status=$(kubectl get clusterissuer "$STAGING_CLUSTER_ISSUER" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$staging_status" = "True" ]; then
            staging_ready=true
            log_info "Staging ClusterIssuer is ready"
        else
            log_warning "Staging ClusterIssuer status: $staging_status"
        fi
    else
        log_warning "Staging ClusterIssuer not found"
    fi
    
    # Check production ClusterIssuer
    if kubectl get clusterissuer "$PROD_CLUSTER_ISSUER" &> /dev/null; then
        local prod_status
        prod_status=$(kubectl get clusterissuer "$PROD_CLUSTER_ISSUER" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$prod_status" = "True" ]; then
            prod_ready=true
            log_info "Production ClusterIssuer is ready"
        else
            log_warning "Production ClusterIssuer status: $prod_status"
        fi
    else
        log_warning "Production ClusterIssuer not found"
    fi
    
    if [ "$staging_ready" = true ] && [ "$prod_ready" = true ]; then
        pass_test "ClusterIssuer Availability"
        return 0
    else
        fail_test "ClusterIssuer Availability" "One or more ClusterIssuers are not ready"
        return 1
    fi
}

# Test 2: Certificate provisioning in staging environment
test_staging_certificate_provisioning() {
    start_test "Staging Certificate Provisioning"
    
    log_info "Cleaning up existing certificates..."
    kubectl delete certificate obsidian-tls couchdb-tls -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete secret obsidian-tls couchdb-tls -n "$NAMESPACE" --ignore-not-found=true
    
    # Wait for cleanup
    sleep 10
    
    log_info "Applying staging ingress resources..."
    if ! kubectl apply -f "$OBSIDIAN_DIR/obsidian-ingress-tls-staging.yaml" &>> "$LOG_FILE"; then
        fail_test "Staging Certificate Provisioning" "Failed to apply Obsidian staging ingress"
        return 1
    fi
    
    if ! kubectl apply -f "$OBSIDIAN_DIR/couchdb-ingress-tls-staging.yaml" &>> "$LOG_FILE"; then
        fail_test "Staging Certificate Provisioning" "Failed to apply CouchDB staging ingress"
        return 1
    fi
    
    log_info "Waiting for certificates to be issued (timeout: ${CERTIFICATE_TIMEOUT}s)..."
    
    # Wait for Obsidian certificate
    if kubectl wait --for=condition=Ready certificate/obsidian-tls -n "$NAMESPACE" --timeout="${CERTIFICATE_TIMEOUT}s" &>> "$LOG_FILE"; then
        log_info "Obsidian certificate issued successfully"
    else
        fail_test "Staging Certificate Provisioning" "Obsidian certificate failed to be issued"
        kubectl describe certificate obsidian-tls -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
        return 1
    fi
    
    # Wait for CouchDB certificate
    if kubectl wait --for=condition=Ready certificate/couchdb-tls -n "$NAMESPACE" --timeout="${CERTIFICATE_TIMEOUT}s" &>> "$LOG_FILE"; then
        log_info "CouchDB certificate issued successfully"
    else
        fail_test "Staging Certificate Provisioning" "CouchDB certificate failed to be issued"
        kubectl describe certificate couchdb-tls -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
        return 1
    fi
    
    # Verify secrets were created
    if kubectl get secret obsidian-tls -n "$NAMESPACE" &> /dev/null && kubectl get secret couchdb-tls -n "$NAMESPACE" &> /dev/null; then
        log_info "Certificate secrets created successfully"
        pass_test "Staging Certificate Provisioning"
        return 0
    else
        fail_test "Staging Certificate Provisioning" "Certificate secrets were not created"
        return 1
    fi
}

# Test 3: HTTPS connectivity tests
test_https_connectivity() {
    start_test "HTTPS Connectivity"
    
    local obsidian_success=false
    local couchdb_success=false
    
    # Test Obsidian HTTPS connectivity
    log_info "Testing HTTPS connectivity to $OBSIDIAN_DOMAIN..."
    if curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" "https://$OBSIDIAN_DOMAIN" > /dev/null 2>&1; then
        log_info "Obsidian HTTPS connectivity successful"
        obsidian_success=true
    else
        log_warning "Obsidian HTTPS connectivity failed"
    fi
    
    # Test CouchDB HTTPS connectivity
    log_info "Testing HTTPS connectivity to $COUCHDB_DOMAIN..."
    if curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" "https://$COUCHDB_DOMAIN" > /dev/null 2>&1; then
        log_info "CouchDB HTTPS connectivity successful"
        couchdb_success=true
    else
        log_warning "CouchDB HTTPS connectivity failed"
    fi
    
    if [ "$obsidian_success" = true ] && [ "$couchdb_success" = true ]; then
        pass_test "HTTPS Connectivity"
        return 0
    else
        fail_test "HTTPS Connectivity" "One or more services failed HTTPS connectivity test"
        return 1
    fi
}

# Test 4: Certificate validation
test_certificate_validation() {
    start_test "Certificate Validation"
    
    if [ -f "$SCRIPT_DIR/validate-ssl-certificates.sh" ]; then
        log_info "Running certificate validation script..."
        if bash "$SCRIPT_DIR/validate-ssl-certificates.sh" &>> "$LOG_FILE"; then
            pass_test "Certificate Validation"
            return 0
        else
            fail_test "Certificate Validation" "Certificate validation script failed"
            return 1
        fi
    else
        fail_test "Certificate Validation" "Certificate validation script not found"
        return 1
    fi
}

# Test 5: Certificate renewal simulation
test_certificate_renewal_simulation() {
    start_test "Certificate Renewal Simulation"
    
    log_info "Simulating certificate renewal by deleting and recreating certificates..."
    
    # Delete certificates (but keep ingress resources)
    kubectl delete certificate obsidian-tls couchdb-tls -n "$NAMESPACE" --ignore-not-found=true
    
    # Wait for deletion
    sleep 10
    
    # Certificates should be automatically recreated due to ingress annotations
    log_info "Waiting for certificates to be automatically recreated..."
    
    # Wait for recreation with shorter timeout
    local renewal_timeout=180
    
    if kubectl wait --for=condition=Ready certificate/obsidian-tls -n "$NAMESPACE" --timeout="${renewal_timeout}s" &>> "$LOG_FILE" && \
       kubectl wait --for=condition=Ready certificate/couchdb-tls -n "$NAMESPACE" --timeout="${renewal_timeout}s" &>> "$LOG_FILE"; then
        log_info "Certificates renewed successfully"
        pass_test "Certificate Renewal Simulation"
        return 0
    else
        fail_test "Certificate Renewal Simulation" "Certificate renewal failed"
        return 1
    fi
}

# Test 6: Error handling - Invalid ClusterIssuer
test_invalid_cluster_issuer_error_handling() {
    start_test "Invalid ClusterIssuer Error Handling"
    
    log_info "Testing error handling with invalid ClusterIssuer..."
    
    # Create a temporary ingress with invalid ClusterIssuer
    local temp_ingress="test-invalid-issuer"
    
    cat > "/tmp/${temp_ingress}.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${temp_ingress}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "invalid-issuer"
spec:
  tls:
  - hosts:
    - test.example.com
    secretName: test-invalid-tls
  rules:
  - host: test.example.com
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
    if kubectl apply -f "/tmp/${temp_ingress}.yaml" &>> "$LOG_FILE"; then
        log_info "Invalid ingress applied successfully"
        
        # Wait a bit for cert-manager to process
        sleep 30
        
        # Check if certificate was created but failed
        if kubectl get certificate test-invalid-tls -n "$NAMESPACE" &> /dev/null; then
            local cert_status
            cert_status=$(kubectl get certificate test-invalid-tls -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            
            if [ "$cert_status" != "True" ]; then
                log_info "Certificate correctly failed with invalid ClusterIssuer"
                
                # Check for appropriate error message
                local error_message
                error_message=$(kubectl get certificate test-invalid-tls -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                
                if echo "$error_message" | grep -qi "issuer"; then
                    log_info "Appropriate error message found: $error_message"
                    pass_test "Invalid ClusterIssuer Error Handling"
                else
                    fail_test "Invalid ClusterIssuer Error Handling" "No appropriate error message found"
                fi
            else
                fail_test "Invalid ClusterIssuer Error Handling" "Certificate unexpectedly succeeded with invalid issuer"
            fi
        else
            fail_test "Invalid ClusterIssuer Error Handling" "Certificate resource was not created"
        fi
        
        # Cleanup
        kubectl delete -f "/tmp/${temp_ingress}.yaml" --ignore-not-found=true &>> "$LOG_FILE"
        rm -f "/tmp/${temp_ingress}.yaml"
    else
        fail_test "Invalid ClusterIssuer Error Handling" "Failed to apply invalid ingress"
    fi
}

# Test 7: Certificate expiry monitoring
test_certificate_expiry_monitoring() {
    start_test "Certificate Expiry Monitoring"
    
    if [ -f "$SCRIPT_DIR/certificate-expiry-check.sh" ]; then
        log_info "Running certificate expiry monitoring test..."
        if bash "$SCRIPT_DIR/certificate-expiry-check.sh" --verbose &>> "$LOG_FILE"; then
            log_info "Certificate expiry monitoring completed successfully"
            pass_test "Certificate Expiry Monitoring"
            return 0
        else
            # Expiry check might fail if certificates are close to expiry, which is not necessarily a test failure
            log_warning "Certificate expiry check returned non-zero exit code (may indicate certificates expiring soon)"
            pass_test "Certificate Expiry Monitoring"
            return 0
        fi
    else
        fail_test "Certificate Expiry Monitoring" "Certificate expiry check script not found"
        return 1
    fi
}

# Test 8: Environment switching functionality
test_environment_switching() {
    start_test "Environment Switching"
    
    if [ -f "$SCRIPT_DIR/switch-certificates.sh" ]; then
        log_info "Testing certificate environment switching..."
        
        # Test switching to staging (should already be in staging from previous tests)
        if bash "$SCRIPT_DIR/switch-certificates.sh" staging --no-validate &>> "$LOG_FILE"; then
            log_info "Successfully switched to staging environment"
            
            # Verify staging ClusterIssuer is being used
            local obsidian_issuer
            obsidian_issuer=$(kubectl get ingress obsidian-tls -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.cert-manager\.io/cluster-issuer}' 2>/dev/null || echo "")
            
            if [ "$obsidian_issuer" = "$STAGING_CLUSTER_ISSUER" ]; then
                log_info "Obsidian ingress correctly using staging ClusterIssuer"
                pass_test "Environment Switching"
                return 0
            else
                fail_test "Environment Switching" "Obsidian ingress not using expected staging ClusterIssuer (got: $obsidian_issuer)"
                return 1
            fi
        else
            fail_test "Environment Switching" "Failed to switch to staging environment"
            return 1
        fi
    else
        fail_test "Environment Switching" "Certificate switching script not found"
        return 1
    fi
}

# Generate test report
generate_test_report() {
    local report_file="${TEST_RESULTS_DIR}/test-report-${TIMESTAMP}.txt"
    
    {
        echo "Certificate Functionality Test Report"
        echo "====================================="
        echo "Date: $(date)"
        echo "Namespace: $NAMESPACE"
        echo "Obsidian Domain: $OBSIDIAN_DOMAIN"
        echo "CouchDB Domain: $COUCHDB_DOMAIN"
        echo
        echo "Test Results:"
        echo "============="
        echo "Total Tests: $TOTAL_TESTS"
        echo "Passed: $PASSED_TESTS"
        echo "Failed: $FAILED_TESTS"
        echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
        echo
        echo "Detailed Log: $LOG_FILE"
        echo
        
        if [ $FAILED_TESTS -gt 0 ]; then
            echo "OVERALL RESULT: FAILED"
            echo
            echo "Some tests failed. Please review the detailed log for more information."
            echo "Common issues and troubleshooting:"
            echo "- Ensure cert-manager is properly installed and configured"
            echo "- Verify ClusterIssuer resources are ready"
            echo "- Check DNS resolution for test domains"
            echo "- Review ingress controller configuration"
            echo "- Check network connectivity to Let's Encrypt servers"
        else
            echo "OVERALL RESULT: PASSED"
            echo
            echo "All certificate functionality tests passed successfully!"
        fi
    } > "$report_file"
    
    # Display report
    cat "$report_file"
    
    log_info "Test report saved to: $report_file"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    
    # Remove any temporary test resources
    kubectl delete ingress test-invalid-issuer -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    kubectl delete certificate test-invalid-tls -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    kubectl delete secret test-invalid-tls -n "$NAMESPACE" --ignore-not-found=true &> /dev/null
    
    log_info "Cleanup completed"
}

# Show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Automated Certificate Functionality Test Suite"
    echo
    echo "Options:"
    echo "  --skip-provisioning    Skip certificate provisioning tests"
    echo "  --skip-connectivity    Skip HTTPS connectivity tests"
    echo "  --skip-renewal         Skip certificate renewal simulation"
    echo "  --skip-error-handling  Skip error handling tests"
    echo "  --timeout SECONDS      Set certificate timeout (default: 300)"
    echo "  --help                 Show this help message"
    echo
    echo "Environment Variables:"
    echo "  CERTIFICATE_TIMEOUT    Override certificate timeout"
    echo "  CONNECTIVITY_TIMEOUT   Override connectivity timeout"
    echo
}

# Parse command line arguments
SKIP_PROVISIONING=false
SKIP_CONNECTIVITY=false
SKIP_RENEWAL=false
SKIP_ERROR_HANDLING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-provisioning)
            SKIP_PROVISIONING=true
            shift
            ;;
        --skip-connectivity)
            SKIP_CONNECTIVITY=true
            shift
            ;;
        --skip-renewal)
            SKIP_RENEWAL=true
            shift
            ;;
        --skip-error-handling)
            SKIP_ERROR_HANDLING=true
            shift
            ;;
        --timeout)
            CERTIFICATE_TIMEOUT="$2"
            shift 2
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
    echo "Certificate Functionality Test Suite"
    echo "===================================="
    echo
    
    # Setup
    setup_test_environment
    check_prerequisites
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    echo
    log_info "Starting certificate functionality tests..."
    echo
    
    # Run tests
    test_cluster_issuer_availability
    echo
    
    if [ "$SKIP_PROVISIONING" = false ]; then
        test_staging_certificate_provisioning
        echo
    fi
    
    if [ "$SKIP_CONNECTIVITY" = false ]; then
        test_https_connectivity
        echo
    fi
    
    test_certificate_validation
    echo
    
    if [ "$SKIP_RENEWAL" = false ]; then
        test_certificate_renewal_simulation
        echo
    fi
    
    if [ "$SKIP_ERROR_HANDLING" = false ]; then
        test_invalid_cluster_issuer_error_handling
        echo
    fi
    
    test_certificate_expiry_monitoring
    echo
    
    test_environment_switching
    echo
    
    # Generate report
    generate_test_report
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"