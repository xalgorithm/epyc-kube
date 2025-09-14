#!/bin/bash

# Test available packages in WordPress container (Debian Trixie)

set -euo pipefail

NAMESPACE="ethosenv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "🔍 Testing Debian Packages in WordPress Container"
echo ""

# Find WordPress pod
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$WORDPRESS_POD" ]; then
    log_error "WordPress pod not found"
    exit 1
fi

log_info "Testing packages in pod: $WORDPRESS_POD"

# Check OS version
log_info "Checking OS version..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /etc/os-release

echo ""
log_info "Checking available MySQL client packages..."

# Test different MySQL client package names
MYSQL_PACKAGES=(
    "mysql-client"
    "default-mysql-client" 
    "mariadb-client"
    "mysql-client-8.0"
    "mysql-client-core-8.0"
)

kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- apt-get update >/dev/null 2>&1

for package in "${MYSQL_PACKAGES[@]}"; do
    echo -n "Testing $package: "
    if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- apt-cache show "$package" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Available${NC}"
    else
        echo -e "${RED}❌ Not available${NC}"
    fi
done

echo ""
log_info "Testing package installation..."

# Try to install the most likely candidates
for package in "default-mysql-client" "mariadb-client" "mysql-client"; do
    log_info "Attempting to install $package..."
    if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- apt-get install -y "$package" >/dev/null 2>&1; then
        log_success "✅ Successfully installed $package"
        
        # Test mysql command
        if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- which mysql >/dev/null 2>&1; then
            log_success "✅ mysql command is available"
            kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- mysql --version
        else
            log_warning "⚠️  mysql command not found after installing $package"
        fi
        break
    else
        log_warning "⚠️  Failed to install $package"
    fi
done

echo ""
log_info "Checking other required packages..."

# Test other packages
OTHER_PACKAGES=("curl" "less" "wget")

for package in "${OTHER_PACKAGES[@]}"; do
    echo -n "Testing $package: "
    if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- which "$package" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Already installed${NC}"
    elif kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- apt-cache show "$package" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Available but not installed${NC}"
    else
        echo -e "${RED}❌ Not available${NC}"
    fi
done

echo ""
log_success "Package testing completed!"