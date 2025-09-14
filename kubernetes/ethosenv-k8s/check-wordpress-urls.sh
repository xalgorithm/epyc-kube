#!/bin/bash

# Check current WordPress URLs in database

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

echo "🔍 WordPress URL Checker"
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

# Check core WordPress URLs
log_info "Core WordPress URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null

echo ""
log_info "Searching for URLs with port 8080:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%:8080%';" 2>/dev/null

echo ""
log_info "Searching for localhost URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%localhost%';" 2>/dev/null

echo ""
log_info "Searching for ethos.gray-beard.com URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%ethos.gray-beard.com%';" 2>/dev/null

echo ""
log_success "URL check completed!"