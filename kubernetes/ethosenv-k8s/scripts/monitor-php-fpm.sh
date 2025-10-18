#!/bin/bash

# Monitor PHP-FPM Processes and Status

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

echo "📊 PHP-FPM Process Monitor"
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
log_info "⚙️  PHP-FPM Configuration:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- cat /usr/local/etc/php-fpm.d/www.conf 2>/dev/null | grep -E "(pm\.|max_children|start_servers|spare_servers)" || log_warning "Could not read PHP-FPM configuration"

echo ""
log_info "🔄 PHP-FPM Process Status:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- ps aux | grep -E "(php-fpm|PID)" || log_warning "Could not get PHP-FPM processes"

echo ""
log_info "📈 PHP-FPM Pool Status (if available):"
# Try to get PHP-FPM status page
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- curl -s http://localhost/status 2>/dev/null || {
    log_warning "PHP-FPM status page not available"
    echo "Status page can be enabled by configuring pm.status_path in PHP-FPM"
}

echo ""
log_info "🏥 PHP-FPM Health Check:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- curl -s http://localhost/ping 2>/dev/null || {
    log_warning "PHP-FPM ping not available"
    echo "Ping can be enabled by configuring ping.path in PHP-FPM"
}

echo ""
log_info "📊 System Resources:"
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
echo 'Memory Usage:'
free -h
echo ''
echo 'CPU Load:'
uptime
echo ''
echo 'Disk Usage:'
df -h /var/www/html
"

echo ""
log_info "🔍 PHP-FPM Logs (last 10 lines):"
kubectl logs "$WORDPRESS_POD" -n "$NAMESPACE" --tail=10 | grep -i "fpm\|php" || log_warning "No recent PHP-FPM logs found"

echo ""
log_info "📝 Monitoring Commands:"
echo "# Watch PHP-FPM processes:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- watch 'ps aux | grep php-fpm'"
echo ""
echo "# Monitor PHP-FPM logs:"
echo "kubectl logs -f $WORDPRESS_POD -n $NAMESPACE"
echo ""
echo "# Check PHP-FPM configuration:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- cat /usr/local/etc/php-fpm.d/www.conf"

echo ""
log_success "PHP-FPM monitoring completed!"