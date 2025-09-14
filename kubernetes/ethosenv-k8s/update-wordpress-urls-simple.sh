#!/bin/bash

# Simple WordPress URL Update Script
# Quick update of core WordPress URLs from http://localhost to https://ethos.gray-beard.com

set -euo pipefail

NAMESPACE="ethosenv"
OLD_URL="http://localhost"
NEW_URL="https://ethos.gray-beard.com"

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

echo "⚡ Simple WordPress URL Update"
echo "📝 $OLD_URL → $NEW_URL"
echo ""

# Find MySQL pod
MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MYSQL_POD" ]; then
    log_error "MySQL pod not found"
    exit 1
fi

log_info "MySQL pod: $MYSQL_POD"

# Get credentials
DB_USER=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_USER}' | base64 -d)
DB_PASSWORD=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)
DB_NAME=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_DATABASE}' | base64 -d)

# Show current URLs
log_info "Current URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null || log_warning "Could not retrieve current URLs"

# Update core URLs
log_info "Updating WordPress URLs..."
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "
UPDATE wp_options SET option_value = '$NEW_URL' WHERE option_name = 'home';
UPDATE wp_options SET option_value = '$NEW_URL' WHERE option_name = 'siteurl';
" 2>/dev/null

# Verify update
log_info "Updated URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null

log_success "✅ Core WordPress URLs updated!"
log_info "🌐 Site should now be accessible at: $NEW_URL"
log_warning "⚠️  For complete migration, run: ./update-wordpress-urls.sh"