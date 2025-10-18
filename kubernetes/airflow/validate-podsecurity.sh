#!/bin/bash

# Validate PodSecurity compliance for PostgreSQL configurations
# This script checks if the configurations meet "restricted" PodSecurity policy requirements

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

# Function to check security context in YAML file
check_security_context() {
    local file="$1"
    local component="$2"
    
    log_info "Checking PodSecurity compliance for $component ($file)..."
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        log_error "File $file not found"
        return 1
    fi
    
    local issues=0
    
    # Check for allowPrivilegeEscalation: false
    if ! grep -q "allowPrivilegeEscalation: false" "$file"; then
        log_error "Missing: allowPrivilegeEscalation: false"
        issues=$((issues + 1))
    else
        log_success "✓ allowPrivilegeEscalation: false"
    fi
    
    # Check for capabilities drop ALL
    if ! grep -A2 "capabilities:" "$file" | grep -q "- ALL"; then
        log_error "Missing: capabilities.drop: [ALL]"
        issues=$((issues + 1))
    else
        log_success "✓ capabilities.drop: [ALL]"
    fi
    
    # Check for seccompProfile
    if ! grep -q "seccompProfile:" "$file"; then
        log_error "Missing: seccompProfile"
        issues=$((issues + 1))
    elif ! grep -A1 "seccompProfile:" "$file" | grep -q "type: RuntimeDefault"; then
        log_error "Missing: seccompProfile.type: RuntimeDefault"
        issues=$((issues + 1))
    else
        log_success "✓ seccompProfile.type: RuntimeDefault"
    fi
    
    # Check for runAsNonRoot
    if ! grep -q "runAsNonRoot: true" "$file"; then
        log_error "Missing: runAsNonRoot: true"
        issues=$((issues + 1))
    else
        log_success "✓ runAsNonRoot: true"
    fi
    
    # Check for runAsUser (should be non-zero)
    if ! grep -q "runAsUser: [1-9]" "$file"; then
        log_error "Missing or invalid: runAsUser (must be non-zero)"
        issues=$((issues + 1))
    else
        log_success "✓ runAsUser: non-zero"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "✅ $component passes PodSecurity 'restricted' policy checks"
    else
        log_error "❌ $component has $issues PodSecurity policy violations"
    fi
    
    return $issues
}

# Function to test deployment with dry-run
test_deployment() {
    local file="$1"
    local component="$2"
    
    log_info "Testing deployment for $component with dry-run..."
    
    if kubectl apply --dry-run=client -f "$file" >/dev/null 2>&1; then
        log_success "✓ $component YAML is valid"
    else
        log_error "✗ $component YAML has syntax errors"
        kubectl apply --dry-run=client -f "$file"
        return 1
    fi
}

# Main validation function
main() {
    log_info "Starting PodSecurity compliance validation..."
    
    local total_issues=0
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check PostgreSQL Primary
    if check_security_context "$script_dir/postgresql-primary.yaml" "PostgreSQL Primary"; then
        test_deployment "$script_dir/postgresql-primary.yaml" "PostgreSQL Primary"
    fi
    total_issues=$((total_issues + $?))
    
    echo
    
    # Check PostgreSQL Standby
    if check_security_context "$script_dir/postgresql-standby.yaml" "PostgreSQL Standby"; then
        test_deployment "$script_dir/postgresql-standby.yaml" "PostgreSQL Standby"
    fi
    total_issues=$((total_issues + $?))
    
    echo
    
    # Summary
    if [[ $total_issues -eq 0 ]]; then
        log_success "🎉 All PostgreSQL configurations are PodSecurity 'restricted' compliant!"
        log_info "You can now deploy PostgreSQL without security policy violations."
    else
        log_error "❌ Found $total_issues PodSecurity policy violations"
        log_info "Please fix the issues above before deploying."
        return 1
    fi
    
    # Additional recommendations
    echo
    log_info "Additional recommendations:"
    echo "1. Ensure your namespace has the correct PodSecurity labels"
    echo "2. Consider using a dedicated service account with minimal permissions"
    echo "3. Review network policies for additional security"
    echo "4. Monitor security events in your cluster"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi