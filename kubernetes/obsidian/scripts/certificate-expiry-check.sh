#!/bin/bash

# Certificate Expiry Monitoring Script
# Checks SSL certificate expiration dates and alerts when certificates expire soon

set -e

NAMESPACE="obsidian"
SECRETS=("obsidian-tls" "couchdb-tls")
WARNING_DAYS=${WARNING_DAYS:-30}
CRITICAL_DAYS=${CRITICAL_DAYS:-7}

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

# Function to check if required tools are available
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if ! command -v date &> /dev/null; then
        missing_tools+=("date")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to get certificate expiration date from secret
get_cert_expiry() {
    local secret_name=$1
    local namespace=$2
    
    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        echo "SECRET_NOT_FOUND"
        return
    fi
    
    local cert_data
    cert_data=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
    
    if [ -z "$cert_data" ]; then
        echo "CERT_DATA_NOT_FOUND"
        return
    fi
    
    local expiry_date
    expiry_date=$(echo "$cert_data" | base64 -d | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)
    
    if [ -z "$expiry_date" ]; then
        echo "EXPIRY_DATE_NOT_FOUND"
        return
    fi
    
    echo "$expiry_date"
}

# Function to calculate days until expiry
calculate_days_until_expiry() {
    local expiry_date=$1
    
    # Handle different date formats across platforms
    local expiry_epoch
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
    else
        # Linux
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    fi
    
    if [ -z "$expiry_epoch" ]; then
        echo "DATE_PARSE_ERROR"
        return
    fi
    
    local current_epoch
    current_epoch=$(date +%s)
    
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    echo "$days_until_expiry"
}

# Function to get certificate subject and issuer
get_cert_details() {
    local secret_name=$1
    local namespace=$2
    
    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        return
    fi
    
    local cert_data
    cert_data=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
    
    if [ -z "$cert_data" ]; then
        return
    fi
    
    echo "$cert_data" | base64 -d | openssl x509 -subject -issuer -noout 2>/dev/null
}

# Function to send alert (placeholder for integration with alerting systems)
send_alert() {
    local severity=$1
    local message=$2
    
    # This is a placeholder function. In a real environment, you would integrate
    # with your alerting system (email, Slack, PagerDuty, etc.)
    
    case $severity in
        "critical")
            log_error "CRITICAL ALERT: $message"
            ;;
        "warning")
            log_warning "WARNING ALERT: $message"
            ;;
        *)
            log_info "ALERT: $message"
            ;;
    esac
    
    # Example integrations (uncomment and configure as needed):
    
    # Email alert
    # echo "$message" | mail -s "Certificate Alert - $severity" admin@example.com
    
    # Slack webhook
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"text\":\"$message\"}" \
    #   YOUR_SLACK_WEBHOOK_URL
    
    # Custom webhook
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"severity\":\"$severity\",\"message\":\"$message\"}" \
    #   YOUR_WEBHOOK_URL
}

# Function to check a single certificate
check_certificate() {
    local secret_name=$1
    local namespace=$2
    
    log_info "Checking certificate: $secret_name"
    
    local expiry_date
    expiry_date=$(get_cert_expiry "$secret_name" "$namespace")
    
    case $expiry_date in
        "SECRET_NOT_FOUND")
            log_error "Secret '$secret_name' not found in namespace '$namespace'"
            send_alert "critical" "Certificate secret '$secret_name' not found in namespace '$namespace'"
            return 1
            ;;
        "CERT_DATA_NOT_FOUND")
            log_error "Certificate data not found in secret '$secret_name'"
            send_alert "critical" "Certificate data not found in secret '$secret_name'"
            return 1
            ;;
        "EXPIRY_DATE_NOT_FOUND")
            log_error "Could not parse expiry date from certificate in secret '$secret_name'"
            send_alert "critical" "Could not parse expiry date from certificate in secret '$secret_name'"
            return 1
            ;;
    esac
    
    local days_until_expiry
    days_until_expiry=$(calculate_days_until_expiry "$expiry_date")
    
    if [ "$days_until_expiry" = "DATE_PARSE_ERROR" ]; then
        log_error "Could not parse expiry date: $expiry_date"
        send_alert "critical" "Could not parse expiry date for certificate '$secret_name': $expiry_date"
        return 1
    fi
    
    # Get certificate details
    local cert_details
    cert_details=$(get_cert_details "$secret_name" "$namespace")
    
    # Check expiry status
    if [ "$days_until_expiry" -lt 0 ]; then
        log_error "Certificate '$secret_name' has EXPIRED (expired $((days_until_expiry * -1)) days ago)"
        send_alert "critical" "Certificate '$secret_name' has EXPIRED (expired $((days_until_expiry * -1)) days ago)"
        return 1
    elif [ "$days_until_expiry" -le "$CRITICAL_DAYS" ]; then
        log_error "Certificate '$secret_name' expires in $days_until_expiry days (CRITICAL)"
        send_alert "critical" "Certificate '$secret_name' expires in $days_until_expiry days"
        return 1
    elif [ "$days_until_expiry" -le "$WARNING_DAYS" ]; then
        log_warning "Certificate '$secret_name' expires in $days_until_expiry days (WARNING)"
        send_alert "warning" "Certificate '$secret_name' expires in $days_until_expiry days"
        return 1
    else
        log_success "Certificate '$secret_name' is valid (expires in $days_until_expiry days)"
    fi
    
    # Show certificate details if verbose mode
    if [ "$VERBOSE" = "true" ]; then
        echo "  Expiry Date: $expiry_date"
        if [ -n "$cert_details" ]; then
            echo "  $cert_details"
        fi
        echo
    fi
    
    return 0
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --warning-days DAYS    Days before expiry to show warning (default: 30)"
    echo "  --critical-days DAYS   Days before expiry to show critical alert (default: 7)"
    echo "  --namespace NAMESPACE  Kubernetes namespace to check (default: obsidian)"
    echo "  --verbose              Show detailed certificate information"
    echo "  --help                 Show this help message"
    echo
    echo "Environment Variables:"
    echo "  WARNING_DAYS          Override default warning threshold"
    echo "  CRITICAL_DAYS         Override default critical threshold"
    echo
    echo "Exit Codes:"
    echo "  0 - All certificates are valid and not expiring soon"
    echo "  1 - One or more certificates are expired or expiring soon"
    echo "  2 - Script error or invalid arguments"
    echo
}

# Parse command line arguments
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --warning-days)
            WARNING_DAYS="$2"
            shift 2
            ;;
        --critical-days)
            CRITICAL_DAYS="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 2
            ;;
    esac
done

# Validate numeric arguments
if ! [[ "$WARNING_DAYS" =~ ^[0-9]+$ ]] || [ "$WARNING_DAYS" -lt 1 ]; then
    log_error "Warning days must be a positive integer"
    exit 2
fi

if ! [[ "$CRITICAL_DAYS" =~ ^[0-9]+$ ]] || [ "$CRITICAL_DAYS" -lt 1 ]; then
    log_error "Critical days must be a positive integer"
    exit 2
fi

if [ "$CRITICAL_DAYS" -gt "$WARNING_DAYS" ]; then
    log_error "Critical days ($CRITICAL_DAYS) cannot be greater than warning days ($WARNING_DAYS)"
    exit 2
fi

# Main execution
main() {
    echo "========================================="
    echo "Certificate Expiry Check"
    echo "========================================="
    echo
    
    log_info "Checking certificates in namespace: $NAMESPACE"
    log_info "Warning threshold: $WARNING_DAYS days"
    log_info "Critical threshold: $CRITICAL_DAYS days"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 2
    fi
    
    local exit_code=0
    local total_certs=0
    local failed_certs=0
    
    # Check each certificate
    for secret in "${SECRETS[@]}"; do
        total_certs=$((total_certs + 1))
        if ! check_certificate "$secret" "$NAMESPACE"; then
            failed_certs=$((failed_certs + 1))
            exit_code=1
        fi
        echo
    done
    
    # Summary
    echo "========================================="
    echo "Summary"
    echo "========================================="
    
    if [ $exit_code -eq 0 ]; then
        log_success "All $total_certs certificates are valid and not expiring soon"
    else
        log_error "$failed_certs out of $total_certs certificates have issues"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"