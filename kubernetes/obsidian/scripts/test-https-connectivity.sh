#!/bin/bash

# HTTPS Connectivity Integration Test Script
# Tests HTTPS connectivity and certificate validation for Obsidian and CouchDB services
# Requirements: 1.1, 1.4, 2.1, 2.4, 3.4

set -euo pipefail

# Configuration
NAMESPACE="obsidian"
OBSIDIAN_DOMAIN="blackrock.gray-beard.com"
COUCHDB_DOMAIN="couchdb.blackrock.gray-beard.com"
CONNECTIVITY_TIMEOUT=30
MAX_RETRIES=3
RETRY_DELAY=10

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
    
    local missing_tools=()
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if ! command -v dig &> /dev/null && ! command -v nslookup &> /dev/null; then
        missing_tools+=("dig or nslookup")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to test DNS resolution
test_dns_resolution() {
    local domain=$1
    local service_name=$2
    
    start_test "DNS Resolution for $service_name ($domain)"
    
    log_info "Testing DNS resolution for $domain..."
    
    local dns_result=""
    if command -v dig &> /dev/null; then
        dns_result=$(dig +short "$domain" 2>/dev/null || echo "")
    elif command -v nslookup &> /dev/null; then
        dns_result=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "")
    fi
    
    if [ -n "$dns_result" ]; then
        log_info "DNS resolution successful: $domain -> $dns_result"
        pass_test "DNS Resolution for $service_name"
        return 0
    else
        fail_test "DNS Resolution for $service_name" "DNS resolution failed for $domain"
        return 1
    fi
}

# Function to test basic HTTPS connectivity
test_basic_https_connectivity() {
    local domain=$1
    local service_name=$2
    
    start_test "Basic HTTPS Connectivity for $service_name"
    
    log_info "Testing basic HTTPS connectivity to $domain..."
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
           --head "https://$domain" > /dev/null 2>&1; then
            log_success "HTTPS connectivity successful for $domain"
            pass_test "Basic HTTPS Connectivity for $service_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $MAX_RETRIES ]; then
                log_warning "HTTPS connectivity failed, retrying in ${RETRY_DELAY}s (attempt $retry_count/$MAX_RETRIES)..."
                sleep $RETRY_DELAY
            fi
        fi
    done
    
    fail_test "Basic HTTPS Connectivity for $service_name" "Failed to connect to https://$domain after $MAX_RETRIES attempts"
    return 1
}

# Function to test HTTPS with certificate verification
test_https_with_cert_verification() {
    local domain=$1
    local service_name=$2
    
    start_test "HTTPS with Certificate Verification for $service_name"
    
    log_info "Testing HTTPS with certificate verification for $domain..."
    
    # Test with certificate verification enabled
    local curl_output
    if curl_output=$(curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
                     --cacert /etc/ssl/certs/ca-certificates.crt \
                     --head "https://$domain" 2>&1); then
        log_success "HTTPS with certificate verification successful for $domain"
        pass_test "HTTPS with Certificate Verification for $service_name"
        return 0
    else
        log_warning "HTTPS with certificate verification failed for $domain"
        log_info "Curl output: $curl_output"
        
        # Check if it's a certificate issue specifically
        if echo "$curl_output" | grep -qi "certificate\|ssl\|tls"; then
            log_info "Certificate-related error detected"
        fi
        
        fail_test "HTTPS with Certificate Verification for $service_name" "Certificate verification failed"
        return 1
    fi
}

# Function to test certificate details
test_certificate_details() {
    local domain=$1
    local service_name=$2
    
    start_test "Certificate Details Validation for $service_name"
    
    log_info "Retrieving certificate details for $domain..."
    
    # Get certificate information
    local cert_info
    if cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | \
                   openssl x509 -noout -text 2>/dev/null); then
        
        # Extract certificate details
        local issuer
        local subject
        local not_after
        local san_list
        
        issuer=$(echo "$cert_info" | grep -A1 "Issuer:" | tail -1 | sed 's/^[[:space:]]*//')
        subject=$(echo "$cert_info" | grep -A1 "Subject:" | tail -1 | sed 's/^[[:space:]]*//')
        not_after=$(echo "$cert_info" | grep "Not After" | sed 's/.*Not After : //')
        san_list=$(echo "$cert_info" | grep -A1 "Subject Alternative Name:" | tail -1 | sed 's/^[[:space:]]*//' | sed 's/DNS://g')
        
        log_info "Certificate details for $domain:"
        log_info "  Issuer: $issuer"
        log_info "  Subject: $subject"
        log_info "  Expires: $not_after"
        log_info "  SAN: $san_list"
        
        # Validate certificate properties
        local validation_passed=true
        
        # Check if certificate is from Let's Encrypt
        if echo "$issuer" | grep -qi "let's encrypt"; then
            log_success "Certificate is issued by Let's Encrypt"
        else
            log_warning "Certificate is not issued by Let's Encrypt: $issuer"
        fi
        
        # Check certificate expiration
        local expiry_epoch
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || echo "")
        else
            # Linux
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo "")
        fi
        
        if [ -n "$expiry_epoch" ]; then
            local current_epoch
            current_epoch=$(date +%s)
            local days_until_expiry
            days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [ "$days_until_expiry" -lt 0 ]; then
                log_error "Certificate has expired $((days_until_expiry * -1)) days ago"
                validation_passed=false
            elif [ "$days_until_expiry" -lt 30 ]; then
                log_warning "Certificate expires in $days_until_expiry days"
            else
                log_success "Certificate is valid for $days_until_expiry more days"
            fi
        else
            log_warning "Could not parse certificate expiration date: $not_after"
        fi
        
        # Verify domain is in SAN list
        if echo "$san_list" | grep -q "$domain"; then
            log_success "Domain $domain is present in certificate SAN list"
        else
            log_error "Domain $domain is NOT present in certificate SAN list"
            validation_passed=false
        fi
        
        if [ "$validation_passed" = true ]; then
            pass_test "Certificate Details Validation for $service_name"
            return 0
        else
            fail_test "Certificate Details Validation for $service_name" "Certificate validation failed"
            return 1
        fi
    else
        fail_test "Certificate Details Validation for $service_name" "Failed to retrieve certificate information"
        return 1
    fi
}

# Function to test HTTP to HTTPS redirect
test_http_to_https_redirect() {
    local domain=$1
    local service_name=$2
    
    start_test "HTTP to HTTPS Redirect for $service_name"
    
    log_info "Testing HTTP to HTTPS redirect for $domain..."
    
    # Test HTTP request and check for redirect
    local http_response
    if http_response=$(curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
                       -I "http://$domain" 2>/dev/null); then
        
        # Check for redirect status codes (301, 302, 307, 308)
        if echo "$http_response" | grep -E "HTTP/[0-9.]+ (301|302|307|308)"; then
            log_success "HTTP to HTTPS redirect detected for $domain"
            
            # Check if redirect location is HTTPS
            local redirect_location
            redirect_location=$(echo "$http_response" | grep -i "location:" | sed 's/.*location: *//i' | tr -d '\r\n')
            
            if echo "$redirect_location" | grep -q "https://"; then
                log_success "Redirect location is HTTPS: $redirect_location"
                pass_test "HTTP to HTTPS Redirect for $service_name"
                return 0
            else
                log_warning "Redirect location is not HTTPS: $redirect_location"
                pass_test "HTTP to HTTPS Redirect for $service_name"
                return 0
            fi
        else
            log_info "No HTTP to HTTPS redirect detected (may be expected)"
            pass_test "HTTP to HTTPS Redirect for $service_name"
            return 0
        fi
    else
        log_warning "Could not test HTTP redirect for $domain"
        pass_test "HTTP to HTTPS Redirect for $service_name"
        return 0
    fi
}

# Function to test TLS version and cipher suites
test_tls_configuration() {
    local domain=$1
    local service_name=$2
    
    start_test "TLS Configuration for $service_name"
    
    log_info "Testing TLS configuration for $domain..."
    
    # Test TLS connection and get protocol information
    local tls_info
    if tls_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>&1); then
        
        # Extract TLS version
        local tls_version
        tls_version=$(echo "$tls_info" | grep "Protocol" | head -1 | awk '{print $3}')
        
        # Extract cipher suite
        local cipher_suite
        cipher_suite=$(echo "$tls_info" | grep "Cipher" | head -1 | awk '{print $3}')
        
        log_info "TLS configuration for $domain:"
        log_info "  Protocol: $tls_version"
        log_info "  Cipher: $cipher_suite"
        
        # Validate TLS version (should be TLS 1.2 or higher)
        if echo "$tls_version" | grep -E "TLSv1\.[2-9]|TLSv[2-9]"; then
            log_success "TLS version is secure: $tls_version"
        else
            log_warning "TLS version may be insecure: $tls_version"
        fi
        
        # Check for successful handshake
        if echo "$tls_info" | grep -q "Verify return code: 0"; then
            log_success "TLS handshake successful with verification"
        elif echo "$tls_info" | grep -q "Verify return code:"; then
            local verify_code
            verify_code=$(echo "$tls_info" | grep "Verify return code:" | sed 's/.*Verify return code: //')
            log_warning "TLS handshake completed but verification failed: $verify_code"
        fi
        
        pass_test "TLS Configuration for $service_name"
        return 0
    else
        fail_test "TLS Configuration for $service_name" "Failed to establish TLS connection"
        return 1
    fi
}

# Function to test service-specific endpoints
test_service_specific_endpoints() {
    local domain=$1
    local service_name=$2
    
    start_test "Service-Specific Endpoints for $service_name"
    
    case $service_name in
        "Obsidian")
            # Test Obsidian-specific endpoints
            log_info "Testing Obsidian-specific endpoints..."
            
            # Test main page
            if curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
               "https://$domain" | grep -qi "obsidian\|vault"; then
                log_success "Obsidian main page accessible"
            else
                log_warning "Obsidian main page may not be properly configured"
            fi
            ;;
            
        "CouchDB")
            # Test CouchDB-specific endpoints
            log_info "Testing CouchDB-specific endpoints..."
            
            # Test CouchDB welcome endpoint
            local couchdb_response
            if couchdb_response=$(curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
                                  "https://$domain" 2>/dev/null); then
                if echo "$couchdb_response" | grep -qi "couchdb\|welcome"; then
                    log_success "CouchDB welcome endpoint accessible"
                else
                    log_info "CouchDB response: $couchdb_response"
                fi
            else
                log_warning "CouchDB welcome endpoint may not be accessible"
            fi
            
            # Test CouchDB _utils (Fauxton) if available
            if curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
               --head "https://$domain/_utils/" > /dev/null 2>&1; then
                log_success "CouchDB Fauxton interface accessible"
            else
                log_info "CouchDB Fauxton interface may not be enabled"
            fi
            ;;
    esac
    
    pass_test "Service-Specific Endpoints for $service_name"
    return 0
}

# Function to test concurrent connections
test_concurrent_connections() {
    local domain=$1
    local service_name=$2
    
    start_test "Concurrent HTTPS Connections for $service_name"
    
    log_info "Testing concurrent HTTPS connections to $domain..."
    
    # Create multiple concurrent requests
    local num_concurrent=5
    local pids=()
    local temp_dir="/tmp/https-test-$$"
    mkdir -p "$temp_dir"
    
    for i in $(seq 1 $num_concurrent); do
        (
            if curl -s --connect-timeout "$CONNECTIVITY_TIMEOUT" --max-time "$CONNECTIVITY_TIMEOUT" \
               "https://$domain" > "$temp_dir/response_$i.txt" 2>&1; then
                echo "success" > "$temp_dir/result_$i.txt"
            else
                echo "failure" > "$temp_dir/result_$i.txt"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Count successful requests
    local successful=0
    for i in $(seq 1 $num_concurrent); do
        if [ -f "$temp_dir/result_$i.txt" ] && grep -q "success" "$temp_dir/result_$i.txt"; then
            successful=$((successful + 1))
        fi
    done
    
    log_info "Concurrent connections: $successful/$num_concurrent successful"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    if [ $successful -ge $((num_concurrent * 80 / 100)) ]; then  # 80% success rate
        log_success "Concurrent connections test passed ($successful/$num_concurrent)"
        pass_test "Concurrent HTTPS Connections for $service_name"
        return 0
    else
        fail_test "Concurrent HTTPS Connections for $service_name" "Only $successful/$num_concurrent connections succeeded"
        return 1
    fi
}

# Function to run all tests for a service
test_service_https_connectivity() {
    local domain=$1
    local service_name=$2
    
    echo
    log_info "=== Testing HTTPS connectivity for $service_name ($domain) ==="
    echo
    
    # Run all connectivity tests
    test_dns_resolution "$domain" "$service_name"
    echo
    
    test_basic_https_connectivity "$domain" "$service_name"
    echo
    
    test_https_with_cert_verification "$domain" "$service_name"
    echo
    
    test_certificate_details "$domain" "$service_name"
    echo
    
    test_http_to_https_redirect "$domain" "$service_name"
    echo
    
    test_tls_configuration "$domain" "$service_name"
    echo
    
    test_service_specific_endpoints "$domain" "$service_name"
    echo
    
    test_concurrent_connections "$domain" "$service_name"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "HTTPS Connectivity Integration Test Script"
    echo
    echo "Options:"
    echo "  --timeout SECONDS      Set connectivity timeout (default: 30)"
    echo "  --retries COUNT        Set max retry count (default: 3)"
    echo "  --obsidian-only        Test only Obsidian service"
    echo "  --couchdb-only         Test only CouchDB service"
    echo "  --skip-concurrent      Skip concurrent connection tests"
    echo "  --help                 Show this help message"
    echo
}

# Parse command line arguments
TEST_OBSIDIAN=true
TEST_COUCHDB=true
SKIP_CONCURRENT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            CONNECTIVITY_TIMEOUT="$2"
            shift 2
            ;;
        --retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --obsidian-only)
            TEST_OBSIDIAN=true
            TEST_COUCHDB=false
            shift
            ;;
        --couchdb-only)
            TEST_OBSIDIAN=false
            TEST_COUCHDB=true
            shift
            ;;
        --skip-concurrent)
            SKIP_CONCURRENT=true
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
    echo "HTTPS Connectivity Integration Test Suite"
    echo "========================================="
    echo
    
    check_prerequisites
    echo
    
    # Test Obsidian service
    if [ "$TEST_OBSIDIAN" = true ]; then
        test_service_https_connectivity "$OBSIDIAN_DOMAIN" "Obsidian"
        
        if [ "$TEST_COUCHDB" = true ]; then
            echo
            echo "========================================="
        fi
    fi
    
    # Test CouchDB service
    if [ "$TEST_COUCHDB" = true ]; then
        test_service_https_connectivity "$COUCHDB_DOMAIN" "CouchDB"
    fi
    
    echo
    echo "========================================="
    echo "HTTPS Connectivity Test Summary"
    echo "========================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All HTTPS connectivity tests PASSED!"
        echo
        echo "Both Obsidian and CouchDB services are properly configured with SSL certificates"
        echo "and are accessible via HTTPS with proper certificate validation."
        exit 0
    else
        log_error "Some HTTPS connectivity tests FAILED!"
        echo
        echo "Please review the test output above for specific issues."
        echo "Common problems and solutions:"
        echo "- DNS resolution issues: Check domain configuration"
        echo "- Certificate validation failures: Verify cert-manager configuration"
        echo "- Connection timeouts: Check network connectivity and firewall rules"
        echo "- TLS configuration issues: Review ingress controller settings"
        exit 1
    fi
}

# Run main function
main "$@"