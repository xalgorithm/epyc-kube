#!/bin/bash

# SSL Certificate Environment Switching Script
# Switches between staging and production SSL certificates for Obsidian stack

set -e

ENVIRONMENT=${1:-staging}
NAMESPACE="obsidian"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBSIDIAN_DIR="$(dirname "$SCRIPT_DIR")"

# Color codes for output
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
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    # Check if cert-manager is running
    if ! kubectl get pods -n cert-manager | grep -q "cert-manager.*Running"; then
        log_error "cert-manager is not running"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to check ClusterIssuer availability
check_cluster_issuer() {
    local issuer=$1
    log_info "Checking ClusterIssuer: $issuer"
    
    if ! kubectl get clusterissuer "$issuer" &> /dev/null; then
        log_error "ClusterIssuer '$issuer' not found"
        exit 1
    fi
    
    local ready=$(kubectl get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$ready" != "True" ]; then
        log_error "ClusterIssuer '$issuer' is not ready"
        exit 1
    fi
    
    log_success "ClusterIssuer '$issuer' is ready"
}

# Function to delete existing certificates and secrets
cleanup_certificates() {
    log_info "Cleaning up existing certificates and secrets..."
    
    # Delete certificates (this will also clean up associated resources)
    kubectl delete certificate obsidian-tls couchdb-tls -n "$NAMESPACE" --ignore-not-found=true
    
    # Delete secrets (in case they exist without certificates)
    kubectl delete secret obsidian-tls couchdb-tls -n "$NAMESPACE" --ignore-not-found=true
    
    # Wait a moment for cleanup to complete
    sleep 5
    
    log_success "Certificate cleanup completed"
}

# Function to apply ingress resources
apply_ingress_resources() {
    local env=$1
    log_info "Applying ingress resources for $env environment..."
    
    if [ "$env" = "production" ]; then
        kubectl apply -f "$OBSIDIAN_DIR/obsidian-ingress-tls.yaml"
        kubectl apply -f "$OBSIDIAN_DIR/couchdb-ingress-tls.yaml"
    elif [ "$env" = "staging" ]; then
        kubectl apply -f "$OBSIDIAN_DIR/obsidian-ingress-tls-staging.yaml"
        kubectl apply -f "$OBSIDIAN_DIR/couchdb-ingress-tls-staging.yaml"
    else
        log_error "Invalid environment: $env"
        exit 1
    fi
    
    log_success "Ingress resources applied for $env environment"
}

# Function to wait for certificates to be ready
wait_for_certificates() {
    log_info "Waiting for certificates to be issued..."
    
    local timeout=300
    local certificates=("obsidian-tls" "couchdb-tls")
    
    for cert in "${certificates[@]}"; do
        log_info "Waiting for certificate: $cert"
        
        if kubectl wait --for=condition=Ready certificate/"$cert" -n "$NAMESPACE" --timeout="${timeout}s"; then
            log_success "Certificate '$cert' is ready"
        else
            log_error "Certificate '$cert' failed to become ready within ${timeout} seconds"
            log_info "Checking certificate status..."
            kubectl describe certificate "$cert" -n "$NAMESPACE"
            exit 1
        fi
    done
    
    log_success "All certificates are ready"
}

# Function to validate certificates
validate_certificates() {
    log_info "Validating certificates..."
    
    if [ -f "$SCRIPT_DIR/validate-ssl-certificates.sh" ]; then
        if bash "$SCRIPT_DIR/validate-ssl-certificates.sh"; then
            log_success "Certificate validation passed"
        else
            log_warning "Certificate validation failed - check the validation output above"
        fi
    else
        log_warning "Certificate validation script not found, skipping validation"
    fi
}

# Function to show certificate information
show_certificate_info() {
    log_info "Certificate Information:"
    echo
    
    # Show certificate resources
    kubectl get certificates -n "$NAMESPACE" -o wide
    echo
    
    # Show TLS secrets
    kubectl get secrets -n "$NAMESPACE" --field-selector type=kubernetes.io/tls -o wide
    echo
    
    # Show certificate details
    for cert in obsidian-tls couchdb-tls; do
        if kubectl get certificate "$cert" -n "$NAMESPACE" &> /dev/null; then
            echo "Certificate: $cert"
            kubectl get certificate "$cert" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "No status message"
            echo
        fi
    done
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [staging|production] [options]"
    echo
    echo "Environments:"
    echo "  staging     - Use Let's Encrypt staging environment (default)"
    echo "  production  - Use Let's Encrypt production environment"
    echo
    echo "Options:"
    echo "  --no-wait   - Don't wait for certificates to be ready"
    echo "  --no-validate - Don't run certificate validation"
    echo "  --help      - Show this help message"
    echo
    echo "Examples:"
    echo "  $0 staging                    # Switch to staging certificates"
    echo "  $0 production                 # Switch to production certificates"
    echo "  $0 staging --no-wait          # Switch to staging without waiting"
    echo
}

# Parse command line arguments
WAIT_FOR_CERTS=true
VALIDATE_CERTS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        staging|production)
            ENVIRONMENT="$1"
            shift
            ;;
        --no-wait)
            WAIT_FOR_CERTS=false
            shift
            ;;
        --no-validate)
            VALIDATE_CERTS=false
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

# Validate environment parameter
if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    show_usage
    exit 1
fi

# Main execution
main() {
    echo "========================================="
    echo "SSL Certificate Environment Switcher"
    echo "========================================="
    echo
    
    log_info "Switching to $ENVIRONMENT certificates..."
    echo
    
    # Check prerequisites
    check_prerequisites
    echo
    
    # Check appropriate ClusterIssuer
    if [ "$ENVIRONMENT" = "production" ]; then
        check_cluster_issuer "letsencrypt-prod"
    else
        check_cluster_issuer "letsencrypt-staging"
    fi
    echo
    
    # Clean up existing certificates
    cleanup_certificates
    echo
    
    # Apply new ingress resources
    apply_ingress_resources "$ENVIRONMENT"
    echo
    
    # Wait for certificates if requested
    if [ "$WAIT_FOR_CERTS" = true ]; then
        wait_for_certificates
        echo
    fi
    
    # Validate certificates if requested
    if [ "$VALIDATE_CERTS" = true ]; then
        validate_certificates
        echo
    fi
    
    # Show certificate information
    show_certificate_info
    
    log_success "Certificate switch to $ENVIRONMENT environment completed!"
    
    if [ "$ENVIRONMENT" = "staging" ]; then
        log_warning "Note: Staging certificates will show browser warnings as they are not trusted"
    fi
}

# Run main function
main "$@"