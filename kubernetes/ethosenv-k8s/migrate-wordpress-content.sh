#!/bin/bash

# Migrate WordPress Content to Kubernetes
# This script copies the existing WordPress content to the Kubernetes deployment

set -euo pipefail

NAMESPACE="ethosenv"
SOURCE_DIR="../ethosenv/wordpress"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

echo "📦 Migrating WordPress Content to Kubernetes..."
echo ""
log_info "💡 Note: If you encounter extended attribute warnings on macOS,"
log_info "    you can use the alternative migration script: ./migrate-wordpress-content-alt.sh"
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    log_error "Source WordPress directory not found: $SOURCE_DIR"
    exit 1
fi

# Check if WordPress pod is running
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$WORDPRESS_POD" ]; then
    log_error "WordPress pod not found. Please deploy WordPress first."
    exit 1
fi

log_info "Found WordPress pod: $WORDPRESS_POD"

# Check if pod is ready
if ! kubectl wait --for=condition=ready pod/"$WORDPRESS_POD" -n "$NAMESPACE" --timeout=60s; then
    log_error "WordPress pod is not ready"
    exit 1
fi

log_info "Creating temporary archive of WordPress content..."
TEMP_ARCHIVE="/tmp/wordpress-content.tar.gz"
cd "$SOURCE_DIR"

# Create tar archive with macOS-friendly options
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: Use --no-xattrs and --no-mac-metadata to avoid extended attribute warnings
    GNUTAR=$(which gtar 2>/dev/null || which tar)
    if $GNUTAR --version 2>/dev/null | grep -q "GNU tar"; then
        # GNU tar supports --no-xattrs
        $GNUTAR -czf "$TEMP_ARCHIVE" --exclude='.DS_Store' --no-xattrs . 2>/dev/null || \
        $GNUTAR -czf "$TEMP_ARCHIVE" --exclude='.DS_Store' .
    else
        # BSD tar (default on macOS) - suppress warnings
        tar -czf "$TEMP_ARCHIVE" --exclude='.DS_Store' . 2>/dev/null || \
        tar -czf "$TEMP_ARCHIVE" --exclude='.DS_Store' .
    fi
else
    # Linux: Standard tar
    tar -czf "$TEMP_ARCHIVE" --exclude='.DS_Store' .
fi

log_info "Copying WordPress content to pod..."
kubectl cp "$TEMP_ARCHIVE" "$NAMESPACE/$WORDPRESS_POD:/tmp/wordpress-content.tar.gz"

log_info "Extracting WordPress content in pod..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    cd /var/www/html
    # Backup existing wp-config.php if it exists
    if [ -f wp-config.php ]; then
        cp wp-config.php wp-config.php.backup
    fi
    
    # Extract the content (suppress extended attribute warnings)
    tar -xzf /tmp/wordpress-content.tar.gz 2>/dev/null || tar -xzf /tmp/wordpress-content.tar.gz
    
    # Restore the Kubernetes-compatible wp-config.php if we backed it up
    if [ -f wp-config.php.backup ]; then
        mv wp-config.php.backup wp-config.php
    fi
    
    # Set proper ownership
    chown -R www-data:www-data /var/www/html
    
    # Clean up
    rm -f /tmp/wordpress-content.tar.gz
"

# Clean up local temp file
rm -f "$TEMP_ARCHIVE"

log_success "✅ WordPress content migration completed!"

echo ""
log_info "📋 Migration Summary:"
echo "- Source: $SOURCE_DIR"
echo "- Destination: $WORDPRESS_POD:/var/www/html"
echo "- Files copied and ownership set to www-data"

echo ""
log_info "🔍 Verification:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- ls -la /var/www/html"

echo ""
log_info "📝 Next Steps:"
echo "1. Access WordPress through the ingress or port-forward"
echo "2. Complete WordPress setup if this is a fresh installation"
echo "3. If migrating from existing installation, you may need to:"
echo "   - Import the database using the backup scripts"
echo "   - Update WordPress URLs in the database"
echo "   - Check file permissions"

echo ""
log_warning "⚠️  Important Notes:"
echo "1. The wp-config.php has been preserved to use Kubernetes environment variables"
echo "2. Make sure to migrate your database content separately"
echo "3. Update any hardcoded URLs in the database to match your new domain"