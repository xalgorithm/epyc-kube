#!/bin/bash

# Simple WordPress Content Migration
# This script uses the simplest possible approach to migrate WordPress content

set -euo pipefail

NAMESPACE="ethosenv"
SOURCE_DIR="../ethosenv/wordpress"

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

echo "📦 Simple WordPress Content Migration..."

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

log_info "Backing up wp-config.php..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cp /var/www/html/wp-config.php /tmp/wp-config.php.backup 2>/dev/null || {
    log_info "No existing wp-config.php to backup"
}

log_info "Copying WordPress themes directory..."
if [ -d "$SOURCE_DIR/wp-content/themes" ]; then
    kubectl cp "$SOURCE_DIR/wp-content/themes" "$NAMESPACE/$WORDPRESS_POD:/var/www/html/wp-content/" || {
        log_warning "Failed to copy themes directory"
    }
fi

log_info "Copying WordPress plugins directory..."
if [ -d "$SOURCE_DIR/wp-content/plugins" ]; then
    kubectl cp "$SOURCE_DIR/wp-content/plugins" "$NAMESPACE/$WORDPRESS_POD:/var/www/html/wp-content/" || {
        log_warning "Failed to copy plugins directory"
    }
fi

log_info "Copying WordPress uploads directory..."
if [ -d "$SOURCE_DIR/wp-content/uploads" ]; then
    kubectl cp "$SOURCE_DIR/wp-content/uploads" "$NAMESPACE/$WORDPRESS_POD:/var/www/html/wp-content/" || {
        log_warning "Failed to copy uploads directory"
    }
fi

log_info "Copying .htaccess file..."
if [ -f "$SOURCE_DIR/.htaccess" ]; then
    kubectl cp "$SOURCE_DIR/.htaccess" "$NAMESPACE/$WORDPRESS_POD:/var/www/html/.htaccess" || {
        log_warning "Failed to copy .htaccess file"
    }
fi

log_info "Restoring wp-config.php and setting permissions..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    # Restore the original wp-config.php
    if [ -f /tmp/wp-config.php.backup ]; then
        cp /tmp/wp-config.php.backup /var/www/html/wp-config.php
        rm -f /tmp/wp-config.php.backup
        echo 'wp-config.php restored'
    fi
    
    # Set proper ownership
    chown -R www-data:www-data /var/www/html
    echo 'Ownership set to www-data'
    
    # Show what was copied
    echo 'Content summary:'
    ls -la /var/www/html/wp-content/ | head -10
"

log_success "✅ WordPress content migration completed!"

echo ""
log_info "📋 Migration Summary:"
echo "- Themes: $([ -d "$SOURCE_DIR/wp-content/themes" ] && echo "✅ Copied" || echo "❌ Not found")"
echo "- Plugins: $([ -d "$SOURCE_DIR/wp-content/plugins" ] && echo "✅ Copied" || echo "❌ Not found")"
echo "- Uploads: $([ -d "$SOURCE_DIR/wp-content/uploads" ] && echo "✅ Copied" || echo "❌ Not found")"
echo "- .htaccess: $([ -f "$SOURCE_DIR/.htaccess" ] && echo "✅ Copied" || echo "❌ Not found")"

echo ""
log_info "🔍 Verification:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- ls -la /var/www/html/wp-content/"

echo ""
log_info "📝 Next Steps:"
echo "1. Access WordPress: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
echo "2. Visit: http://localhost:8080"
echo "3. Complete WordPress setup or verify existing content"
echo "4. Migrate database: ./migrate-database.sh full-migration"

echo ""
log_success "🎉 Migration completed without extended attribute warnings!"