#!/bin/bash

# Install WP-CLI in existing WordPress container

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

echo "⚡ Installing WP-CLI in Existing WordPress Container"
echo ""

# Find WordPress pod
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

# Check if WP-CLI is already installed
log_info "Checking if WP-CLI is already installed..."
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- test -f /var/www/bin/wp >/dev/null 2>&1; then
    log_success "WP-CLI is already installed!"
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --info --allow-root
    exit 0
fi

# Install WP-CLI
log_info "Installing WP-CLI..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    # Create a local bin directory for www-data user
    mkdir -p /var/www/bin
    
    # Download and install WP-CLI to user-writable location
    curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /var/www/bin/wp
    
    echo 'WP-CLI installed to /var/www/bin/wp'
"

if [ $? -eq 0 ]; then
    log_success "✅ WP-CLI installed successfully!"
else
    log_error "❌ Failed to install WP-CLI"
    exit 1
fi

# Create WP-CLI config
log_info "Creating WP-CLI configuration..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
cat > /var/www/html/wp-cli.yml << 'EOF'
path: /var/www/html
url: https://ethos.gray-beard.com
user: admin
core download:
  locale: en_US
  version: latest
  force: false
EOF

chown www-data:www-data /var/www/html/wp-cli.yml
echo 'WP-CLI configuration created'
"

# Test WP-CLI
log_info "Testing WP-CLI..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --info --allow-root

echo ""
log_success "✅ WP-CLI installation completed!"

echo ""
log_info "🔍 Test Commands:"
echo "# Check WP-CLI info:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp --info --allow-root"
echo ""
echo "# Check WordPress installation:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp core is-installed --allow-root"
echo ""
echo "# List WordPress options:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp option list --allow-root"

echo ""
log_info "📝 Ready to Use:"
echo "1. Run URL update script: ./update-wordpress-urls-advanced.sh"
echo "2. Use WP-CLI commands directly:"
echo "   kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp [command] --allow-root"

echo ""
log_warning "⚠️  Note: WP-CLI will be lost if the pod restarts."
echo "For permanent installation, use: ./redeploy-wordpress-with-wpcli.sh"

echo ""
log_success "🎉 WP-CLI is ready to use!"