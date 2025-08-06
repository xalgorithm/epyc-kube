#!/bin/bash

# SSL Certificate Validation Script for Obsidian Stack
# This script validates SSL certificates for Obsidian and CouchDB services
# Requirements: 1.4, 2.4, 3.4

set -euo pipefail

# Configuration
OBSIDIAN_DOMAIN="blackrock.gray-beard.com"
COUCHDB_DOMAIN="couchdb.blackrock.gray-beard.com"
NAMESPACE="obsidian"
OBSIDIAN_SECRET="obsidian-tls"
COUCHDB_SECRET="couchdb-tls"

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

# Function to check if required tools are available
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again."
        exit 1
    fi
    
    log_success "All prerequisites are available"
}

# Function to validate certificate via HTTPS connection
validate_https_certificate() {
    local domain=$1
    local service_name=$2
    
    log_info "Validating HTTPS certificate for $domain ($service_name)..."
    
    # Test HTTPS connectivity
    if ! curl -s --connect-timeout 10 --max-time 30 "https://$domain" > /dev/null 2>&1; then
        log_error "Failed to connect to https://$domain"
        return 1
    fi
    
    # Get certificate information
    local cert_info
    if ! cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -text 2>/dev/null); then
        log_error "Failed to retrieve certificate information for $domain"
        return 1
    fi
    
    # Extract certificate details
    local issuer
    local subject
    local not_after
    local san_list
    
    issuer=$(echo "$cert_info" | grep -A1 "Issuer:" | tail -1 | sed 's/^[[:space:]]*//')
    subject=$(echo "$cert_info" | grep -A1 "Subject:" | tail -1 | sed 's/^[[:space:]]*//')
    not_after=$(echo "$cert_info" | grep "Not After" | sed 's/.*Not After : //')
    san_list=$(echo "$cert_info" | grep -A1 "Subject Alternative Name:" | tail -1 | sed 's/^[[:space:]]*//' | sed 's/DNS://g')
    
    log_success "Certificate retrieved successfully for $domain"
    echo "  Issuer: $issuer"
    echo "  Subject: $subject"
    echo "  Expires: $not_after"
    echo "  SAN: $san_list"
    
    # Check if certificate is from Let's Encrypt
    if echo "$issuer" | grep -qi "let's encrypt"; then
        log_success "Certificate is issued by Let's Encrypt"
    else
        log_warning "Certificate is not issued by Let's Encrypt: $issuer"
    fi
    
    # Check certificate expiration
    local expiry_epoch
    # Try different date parsing methods for cross-platform compatibility
    if expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null) || \
       expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null); then
        local current_epoch
        current_epoch=$(date +%s)
        local days_until_expiry
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [ "$days_until_expiry" -lt 0 ]; then
            log_error "Certificate has expired $((days_until_expiry * -1)) days ago"
            return 1
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
        return 1
    fi
    
    return 0
}

# Function to check Kubernetes certificate secret
check_k8s_certificate_secret() {
    local secret_name=$1
    local domain=$2
    local service_name=$3
    
    log_info "Checking Kubernetes certificate secret '$secret_name' for $service_name..."
    
    # Check if secret exists
    if ! kubectl get secret "$secret_name" -n "$NAMESPACE" &> /dev/null; then
        log_error "Certificate secret '$secret_name' not found in namespace '$NAMESPACE'"
        return 1
    fi
    
    log_success "Certificate secret '$secret_name' exists"
    
    # Get certificate from secret
    local cert_data
    if ! cert_data=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null); then
        log_error "Failed to retrieve certificate data from secret '$secret_name'"
        return 1
    fi
    
    if [ -z "$cert_data" ]; then
        log_error "Certificate data is empty in secret '$secret_name'"
        return 1
    fi
    
    # Decode and analyze certificate
    local cert_info
    if ! cert_info=$(echo "$cert_data" | base64 -d | openssl x509 -noout -text 2>/dev/null); then
        log_error "Failed to decode certificate from secret '$secret_name'"
        return 1
    fi
    
    # Extract certificate details
    local issuer
    local subject
    local not_after
    
    issuer=$(echo "$cert_info" | grep -A1 "Issuer:" | tail -1 | sed 's/^[[:space:]]*//')
    subject=$(echo "$cert_info" | grep -A1 "Subject:" | tail -1 | sed 's/^[[:space:]]*//')
    not_after=$(echo "$cert_info" | grep "Not After" | sed 's/.*Not After : //')
    
    log_success "Certificate in secret '$secret_name' is valid"
    echo "  Issuer: $issuer"
    echo "  Subject: $subject"
    echo "  Expires: $not_after"
    
    # Check expiration
    local expiry_epoch
    # Try different date parsing methods for cross-platform compatibility
    if expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null) || \
       expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null); then
        local current_epoch
        current_epoch=$(date +%s)
        local days_until_expiry
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [ "$days_until_expiry" -lt 0 ]; then
            log_error "Certificate in secret has expired $((days_until_expiry * -1)) days ago"
            return 1
        elif [ "$days_until_expiry" -lt 30 ]; then
            log_warning "Certificate in secret expires in $days_until_expiry days"
        else
            log_success "Certificate in secret is valid for $days_until_expiry more days"
        fi
    else
        log_warning "Could not parse certificate expiration date from secret: $not_after"
    fi
    
    return 0
}

# Function to check cert-manager certificate resource
check_certificate_resource() {
    local domain=$1
    local service_name=$2
    
    log_info "Checking cert-manager Certificate resources for $service_name..."
    
    # Look for Certificate resources that might match this domain
    local certificates
    if certificates=$(kubectl get certificates -n "$NAMESPACE" -o json 2>/dev/null); then
        local cert_count
        cert_count=$(echo "$certificates" | jq -r --arg domain "$domain" '.items[] | select(.spec.dnsNames[]? == $domain) | .metadata.name' | wc -l)
        
        if [ "$cert_count" -eq 0 ]; then
            log_warning "No Certificate resource found for domain $domain"
        else
            echo "$certificates" | jq -r --arg domain "$domain" '.items[] | select(.spec.dnsNames[]? == $domain) | "\(.metadata.name): \(.status.conditions[]? | select(.type=="Ready") | .status)"' | while read -r cert_status; do
                if echo "$cert_status" | grep -q "True"; then
                    log_success "Certificate resource is ready: $cert_status"
                else
                    log_warning "Certificate resource status: $cert_status"
                fi
            done
        fi
    else
        log_warning "Could not retrieve Certificate resources (cert-manager may not be installed)"
    fi
}

# Function to perform comprehensive validation for a service
validate_service_certificates() {
    local domain=$1
    local secret_name=$2
    local service_name=$3
    
    echo
    log_info "=== Validating certificates for $service_name ($domain) ==="
    
    local validation_passed=true
    
    # Check HTTPS certificate
    if ! validate_https_certificate "$domain" "$service_name"; then
        validation_passed=false
    fi
    
    echo
    
    # Check Kubernetes secret
    if ! check_k8s_certificate_secret "$secret_name" "$domain" "$service_name"; then
        validation_passed=false
    fi
    
    echo
    
    # Check cert-manager Certificate resource
    check_certificate_resource "$domain" "$service_name"
    
    if [ "$validation_passed" = true ]; then
        log_success "All certificate validations passed for $service_name"
        return 0
    else
        log_error "Some certificate validations failed for $service_name"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "SSL Certificate Validation Script for Obsidian Stack"
    echo
    echo "OPTIONS:"
    echo "  -h, --help       Show this help message"
    echo "  -o, --obsidian   Validate only Obsidian certificates"
    echo "  -c, --couchdb    Validate only CouchDB certificates"
    echo "  -v, --verbose    Enable verbose output"
    echo
    echo "Examples:"
    echo "  $0                    # Validate all certificates"
    echo "  $0 --obsidian         # Validate only Obsidian certificates"
    echo "  $0 --couchdb          # Validate only CouchDB certificates"
}

# Main function
main() {
    local validate_obsidian=true
    local validate_couchdb=true
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -o|--obsidian)
                validate_obsidian=true
                validate_couchdb=false
                shift
                ;;
            -c|--couchdb)
                validate_obsidian=false
                validate_couchdb=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "SSL Certificate Validation Script for Obsidian Stack"
    echo "=================================================="
    
    # Check prerequisites
    check_prerequisites
    
    local overall_status=0
    
    # Validate Obsidian certificates
    if [ "$validate_obsidian" = true ]; then
        if ! validate_service_certificates "$OBSIDIAN_DOMAIN" "$OBSIDIAN_SECRET" "Obsidian"; then
            overall_status=1
        fi
        
        if [ "$validate_couchdb" = true ]; then
            echo
            echo "=================================================="
        fi
    fi
    
    # Validate CouchDB certificates
    if [ "$validate_couchdb" = true ]; then
        if ! validate_service_certificates "$COUCHDB_DOMAIN" "$COUCHDB_SECRET" "CouchDB"; then
            overall_status=1
        fi
    fi
    
    echo
    echo "=================================================="
    
    # Final summary
    if [ $overall_status -eq 0 ]; then
        log_success "All SSL certificate validations completed successfully!"
    else
        log_error "Some SSL certificate validations failed. Please check the output above for details."
        echo
        echo "Troubleshooting tips:"
        echo "1. Ensure cert-manager is properly installed and configured"
        echo "2. Check that ClusterIssuer resources are available and ready"
        echo "3. Verify DNS resolution for the domains"
        echo "4. Check ingress controller logs for any issues"
        echo "5. Review cert-manager logs: kubectl logs -n cert-manager deployment/cert-manager"
    fi
    
    exit $overall_status
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi