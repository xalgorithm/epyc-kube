#!/bin/bash

# Configure PHP Upload Limits for WordPress
# Sets upload_max_filesize to 32M and related PHP settings

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

echo "🔧 Configuring PHP Settings for WordPress"
echo "📝 Setting upload_max_filesize to 32M"
echo "⚙️  Configuring PHP-FPM process management"
echo ""

# Step 1: Apply PHP configuration
log_info "1. Applying PHP configuration..."
kubectl apply -f ../09-php-config.yaml

if [ $? -eq 0 ]; then
    log_success "✅ PHP configuration applied"
else
    log_error "❌ Failed to apply PHP configuration"
    exit 1
fi

# Step 2: Update WordPress deployment
log_info "2. Updating WordPress deployment with PHP configuration..."
kubectl apply -f ../05-wordpress-deployment.yaml

if [ $? -eq 0 ]; then
    log_success "✅ WordPress deployment updated"
else
    log_error "❌ Failed to update WordPress deployment"
    exit 1
fi

# Step 3: Wait for rollout to complete
log_info "3. Waiting for WordPress deployment rollout..."
kubectl rollout status deployment/wordpress -n "$NAMESPACE" --timeout=300s

if [ $? -eq 0 ]; then
    log_success "✅ WordPress deployment rollout completed"
else
    log_error "❌ WordPress deployment rollout failed"
    exit 1
fi

# Step 4: Get new pod name
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
log_info "WordPress pod: $WORDPRESS_POD"

# Step 5: Wait for pod to be ready
log_info "4. Waiting for WordPress pod to be ready..."
kubectl wait --for=condition=ready pod/"$WORDPRESS_POD" -n "$NAMESPACE" --timeout=120s

if [ $? -eq 0 ]; then
    log_success "✅ WordPress pod is ready"
else
    log_error "❌ WordPress pod not ready"
    exit 1
fi

# Step 6: Verify PHP configuration
log_info "5. Verifying PHP configuration..."
echo ""
log_info "Current PHP upload settings:"

kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- php -r "
echo 'upload_max_filesize: ' . ini_get('upload_max_filesize') . PHP_EOL;
echo 'post_max_size: ' . ini_get('post_max_size') . PHP_EOL;
echo 'max_execution_time: ' . ini_get('max_execution_time') . PHP_EOL;
echo 'max_input_time: ' . ini_get('max_input_time') . PHP_EOL;
echo 'memory_limit: ' . ini_get('memory_limit') . PHP_EOL;
echo 'max_input_vars: ' . ini_get('max_input_vars') . PHP_EOL;
"

echo ""
log_info "PHP-FPM process management settings:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /usr/local/etc/php-fpm.d/www.conf 2>/dev/null | grep -E "(pm\.|max_children|start_servers|spare_servers)" || log_warning "Could not read PHP-FPM configuration"

# Step 7: Check if configuration files are mounted correctly
log_info "6. Checking PHP configuration files..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- ls -la /usr/local/etc/php/conf.d/ | grep uploads || log_warning "uploads.ini not found in conf.d"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- ls -la /usr/local/etc/php-fpm.d/ | grep www.conf || log_warning "www.conf not found in php-fpm.d"

echo ""
log_info "PHP INI configuration:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /usr/local/etc/php/conf.d/uploads.ini 2>/dev/null || log_warning "Could not read uploads.ini"

echo ""
log_info "PHP-FPM configuration:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /usr/local/etc/php-fpm.d/www.conf 2>/dev/null | head -20 || log_warning "Could not read www.conf"

# Step 8: Update WordPress constants (if WP-CLI is available)
log_info "7. Updating WordPress upload constants..."

# Check if WP-CLI is available
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- test -f /var/www/bin/wp >/dev/null 2>&1; then
    log_info "WP-CLI found, updating WordPress constants..."
    
    # Add WordPress constants for upload limits
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --path=/var/www/html --allow-root config set WP_MEMORY_LIMIT 256M --type=constant 2>/dev/null || log_warning "Could not set WP_MEMORY_LIMIT"
    
    log_success "✅ WordPress constants updated"
else
    log_warning "⚠️  WP-CLI not found. WordPress constants not updated."
    log_info "You can install WP-CLI with: ./run-script.sh install-wpcli-existing"
fi

# Step 9: Create .htaccess rules (if needed)
log_info "8. Checking .htaccess configuration..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
if [ -f /var/www/html/.htaccess ]; then
    if ! grep -q 'upload_max_filesize' /var/www/html/.htaccess; then
        echo '' >> /var/www/html/.htaccess
        echo '# PHP Upload Limits' >> /var/www/html/.htaccess
        echo 'php_value upload_max_filesize 32M' >> /var/www/html/.htaccess
        echo 'php_value post_max_size 32M' >> /var/www/html/.htaccess
        echo 'php_value max_execution_time 300' >> /var/www/html/.htaccess
        echo 'php_value max_input_time 300' >> /var/www/html/.htaccess
        echo 'php_value memory_limit 256M' >> /var/www/html/.htaccess
        echo 'php_value max_input_vars 3000' >> /var/www/html/.htaccess
        echo '.htaccess updated with PHP upload limits'
    else
        echo '.htaccess already contains upload limits'
    fi
else
    echo '.htaccess not found, skipping'
fi
"

echo ""
log_success "✅ PHP upload configuration completed!"

echo ""
log_info "📊 Configuration Summary:"
echo ""
echo "PHP Upload Settings:"
echo "- upload_max_filesize: 32M"
echo "- post_max_size: 32M"
echo "- max_execution_time: 300 seconds"
echo "- max_input_time: 300 seconds"
echo "- memory_limit: 256M"
echo "- max_input_vars: 3000"
echo ""
echo "PHP-FPM Process Management:"
echo "- pm.max_children: 100"
echo "- pm.start_servers: 4"
echo "- pm.min_spare_servers: 2"
echo "- pm.max_spare_servers: 9"
echo "- pm.max_requests: 1000"

echo ""
log_info "🔍 Verification Commands:"
echo "# Check PHP settings:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- php -i | grep -E '(upload_max_filesize|post_max_size|memory_limit)'"
echo ""
echo "# Check configuration file:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- cat /usr/local/etc/php/conf.d/uploads.ini"
echo ""
echo "# Check WordPress upload limits in admin:"
echo "Visit: https://ethos.gray-beard.com/wp-admin/media-new.php"

echo ""
log_info "📝 Next Steps:"
echo "1. Test file uploads in WordPress admin"
echo "2. Check Media > Add New for upload limits"
echo "3. Verify large file uploads work correctly"
echo "4. Monitor PHP error logs if issues occur"

echo ""
log_success "🎉 WordPress is now configured with optimized PHP settings!"
log_info "✅ 32M file uploads enabled"
log_info "✅ PHP-FPM process management optimized"