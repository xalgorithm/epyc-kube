#!/bin/bash

# Advanced WordPress URL Update Script
# Uses WordPress CLI (wp-cli) for safer serialized data handling
# Updates WordPress URLs from http://localhost to https://ethos.gray-beard.com

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

echo "🚀 Advanced WordPress URL Update Script (with WP-CLI)"
echo "📝 Updating URLs from: $OLD_URL"
echo "📝 Updating URLs to: $NEW_URL"
echo ""

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

# Check if wp-cli is available in the WordPress container
log_info "Checking for WP-CLI availability..."
WP_CLI_AVAILABLE=$(kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- test -f /var/www/bin/wp && echo "/var/www/bin/wp" || echo "")

if [ -n "$WP_CLI_AVAILABLE" ]; then
    log_success "WP-CLI found - using advanced method"
    USE_WP_CLI=true
else
    log_warning "WP-CLI not found - installing temporarily"
    USE_WP_CLI=false
    
    # Install wp-cli temporarily
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
        apt-get update
        
        # Try different MySQL client packages for Debian Trixie
        if apt-get install -y curl less default-mysql-client; then
            echo 'Installed default-mysql-client'
        elif apt-get install -y curl less mariadb-client; then
            echo 'Installed mariadb-client'  
        elif apt-get install -y curl less mysql-client; then
            echo 'Installed mysql-client'
        else
            echo 'Warning: Could not install MySQL client, WP-CLI may have limited functionality'
            apt-get install -y curl less
        fi
        
        # Create a local bin directory for www-data user
        mkdir -p /var/www/bin
        
        curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /var/www/bin/wp
    " 2>/dev/null || {
        log_error "Failed to install WP-CLI. Falling back to basic method."
        exec ./update-wordpress-urls.sh
        exit $?
    }
    
    log_success "WP-CLI installed temporarily"
    USE_WP_CLI=true
fi

# Function to execute wp-cli command
execute_wp_cli() {
    local command="$1"
    local description="$2"
    
    log_info "$description"
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root $command
}

# Check WordPress installation
log_info "Verifying WordPress installation..."
if ! kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root core is-installed 2>/dev/null; then
    log_error "WordPress is not properly installed or configured"
    exit 1
fi

log_success "WordPress installation verified"

# Show current configuration
log_info "Current WordPress configuration:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root option get home 2>/dev/null || echo "Home URL not set"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root option get siteurl 2>/dev/null || echo "Site URL not set"

echo ""
log_info "🔄 Starting advanced URL updates with WP-CLI..."

# Create database backup using wp-cli
log_info "Creating database backup..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root db export /tmp/wordpress_backup_$(date +%Y%m%d_%H%M%S).sql 2>/dev/null || {
    log_warning "WP-CLI backup failed, continuing without backup"
}

# Update URLs using wp-cli search-replace (handles serialized data properly)
log_info "1. Updating URLs with WP-CLI search-replace (handles serialized data)..."
execute_wp_cli "search-replace '$OLD_URL' '$NEW_URL' --dry-run" "Performing dry run to check what will be updated"

echo ""
log_warning "⚠️  About to perform actual URL replacement. This will modify your database."
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Operation cancelled by user"
    exit 0
fi

execute_wp_cli "search-replace '$OLD_URL' '$NEW_URL'" "Performing actual URL replacement"

# Update WordPress core URLs specifically
log_info "2. Updating WordPress core URLs..."
execute_wp_cli "option update home '$NEW_URL'" "Setting home URL"
execute_wp_cli "option update siteurl '$NEW_URL'" "Setting site URL"

# Clear all caches
log_info "3. Clearing WordPress caches..."
execute_wp_cli "cache flush" "Flushing WordPress object cache"
execute_wp_cli "transient delete --all" "Deleting all transients"

# Update rewrite rules
log_info "4. Updating rewrite rules..."
execute_wp_cli "rewrite flush" "Flushing rewrite rules"

# Check for common plugins that might need cache clearing
log_info "5. Checking for caching plugins..."
CACHING_PLUGINS=$(kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- wp --path=/var/www/html --allow-root plugin list --status=active --field=name 2>/dev/null | grep -E "(cache|optimize|speed)" || echo "")

if [ -n "$CACHING_PLUGINS" ]; then
    log_info "Found caching plugins: $CACHING_PLUGINS"
    log_warning "You may need to manually clear caches for these plugins"
fi

# Verify the changes
log_info "6. Verifying URL updates..."
NEW_HOME=$(kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root option get home 2>/dev/null)
NEW_SITEURL=$(kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root option get siteurl 2>/dev/null)

echo ""
log_success "✅ URL updates completed!"

echo ""
log_info "📊 Update Results:"
echo "- Home URL: $NEW_HOME"
echo "- Site URL: $NEW_SITEURL"

# Search for any remaining old URLs
log_info "Checking for any remaining old URLs..."
REMAINING_URLS=$(kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root db query "SELECT COUNT(*) as count FROM wp_options WHERE option_value LIKE '%$OLD_URL%'" --skip-column-names 2>/dev/null || echo "0")

if [ "$REMAINING_URLS" -gt 0 ]; then
    log_warning "Found $REMAINING_URLS option(s) still containing old URL - may need manual review"
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root db query "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%$OLD_URL%' LIMIT 5" 2>/dev/null || true
else
    log_success "No remaining old URLs found in wp_options"
fi

echo ""
log_info "🔍 Additional Verification Commands:"
echo "# Check all WordPress URLs:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp --path=/var/www/html --allow-root option list | grep -E '(home|siteurl)'"
echo ""
echo "# Search for any remaining old URLs:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp --path=/var/www/html --allow-root search-replace '$OLD_URL' '$NEW_URL' --dry-run"

echo ""
log_info "📝 Next Steps:"
echo "1. Test the site at: $NEW_URL"
echo "2. Check WordPress admin dashboard: $NEW_URL/wp-admin"
echo "3. Clear any plugin-specific caches"
echo "4. Update any hardcoded URLs in theme files"
echo "5. Update external services (CDN, analytics, etc.)"
echo "6. Test all functionality including:"
echo "   - Image uploads and media library"
echo "   - Contact forms"
echo "   - E-commerce functionality"
echo "   - Social media integrations"

echo ""
log_info "🛠️  Troubleshooting:"
echo "If you encounter issues:"
echo "1. Check .htaccess file for hardcoded URLs"
echo "2. Review theme functions.php for hardcoded URLs"
echo "3. Check plugin settings for URL configurations"
echo "4. Verify SSL certificate is working: $NEW_URL"

echo ""
log_success "🎉 Advanced WordPress URL migration completed!"
log_info "Your WordPress site should now be accessible at: $NEW_URL"