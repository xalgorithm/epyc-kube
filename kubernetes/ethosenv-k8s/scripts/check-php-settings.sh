#!/bin/bash

# Check PHP Settings in WordPress Container

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

echo "🔍 Checking PHP Settings in WordPress"
echo ""

# Find WordPress pod
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$WORDPRESS_POD" ]; then
    log_error "WordPress pod not found"
    exit 1
fi

log_info "WordPress pod: $WORDPRESS_POD"

# Check if pod is ready
if ! kubectl wait --for=condition=ready pod/"$WORDPRESS_POD" -n "$NAMESPACE" --timeout=30s >/dev/null 2>&1; then
    log_error "WordPress pod is not ready"
    exit 1
fi

echo ""
log_info "📊 Current PHP Upload Settings:"
echo ""

kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- php -r "
echo '┌─────────────────────────┬─────────────────┐' . PHP_EOL;
echo '│ Setting                 │ Value           │' . PHP_EOL;
echo '├─────────────────────────┼─────────────────┤' . PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'upload_max_filesize', ini_get('upload_max_filesize'), PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'post_max_size', ini_get('post_max_size'), PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'max_execution_time', ini_get('max_execution_time'), PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'max_input_time', ini_get('max_input_time'), PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'memory_limit', ini_get('memory_limit'), PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'max_input_vars', ini_get('max_input_vars'), PHP_EOL;
printf '│ %-23s │ %-15s │%s', 'file_uploads', ini_get('file_uploads') ? 'On' : 'Off', PHP_EOL;
echo '└─────────────────────────┴─────────────────┘' . PHP_EOL;
"

echo ""
log_info "📁 PHP Configuration Files:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- ls -la /usr/local/etc/php/conf.d/ 2>/dev/null || log_warning "Could not list PHP config directory"

echo ""
log_info "📄 Custom PHP Configuration:"
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- test -f /usr/local/etc/php/conf.d/uploads.ini >/dev/null 2>&1; then
    log_success "✅ uploads.ini found"
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /usr/local/etc/php/conf.d/uploads.ini
else
    log_warning "⚠️  uploads.ini not found"
    echo "Run: ./run-script.sh configure-php-uploads"
fi

echo ""
log_info "⚙️  PHP-FPM Process Management:"
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- test -f /usr/local/etc/php-fpm.d/www.conf >/dev/null 2>&1; then
    log_success "✅ www.conf found"
    echo ""
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /usr/local/etc/php-fpm.d/www.conf | grep -E "(pm\.|max_children|start_servers|spare_servers)" | head -10
else
    log_warning "⚠️  PHP-FPM www.conf not found"
    echo "Run: ./run-script.sh configure-php-uploads"
fi

echo ""
log_info "🌐 WordPress Upload Info:"
echo "Visit WordPress Admin > Media > Add New to see upload limits"
echo "URL: https://ethos.gray-beard.com/wp-admin/media-new.php"

echo ""
log_info "🔧 Configuration Commands:"
echo "# Configure PHP uploads:"
echo "./run-script.sh configure-php-uploads"
echo ""
echo "# Check PHP info:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- php -i | grep -E '(upload|post_max|memory)'"

echo ""
log_success "PHP settings check completed!"