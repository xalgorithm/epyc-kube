#!/bin/bash

# Redeploy WordPress with WP-CLI support

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

echo "🔄 Redeploying WordPress with WP-CLI Support"
echo ""

# Check if WordPress deployment exists
if kubectl get deployment wordpress -n "$NAMESPACE" >/dev/null 2>&1; then
    log_info "Found existing WordPress deployment"
    
    # Scale down to 0 replicas first
    log_info "Scaling down WordPress deployment..."
    kubectl scale deployment wordpress --replicas=0 -n "$NAMESPACE"
    
    # Wait for pods to terminate
    log_info "Waiting for pods to terminate..."
    kubectl wait --for=delete pod -l app=wordpress -n "$NAMESPACE" --timeout=60s || true
    
    log_success "WordPress deployment scaled down"
else
    log_info "No existing WordPress deployment found"
fi

# Apply the updated deployment
log_info "Applying updated WordPress deployment with WP-CLI..."
kubectl apply -f 05-wordpress-deployment.yaml

# Wait for deployment to be ready
log_info "Waiting for WordPress deployment to be ready..."
kubectl wait --for=condition=available deployment/wordpress -n "$NAMESPACE" --timeout=300s

# Get the pod name
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
log_info "WordPress pod: $WORDPRESS_POD"

# Wait for pod to be ready
log_info "Waiting for WordPress pod to be ready..."
kubectl wait --for=condition=ready pod/"$WORDPRESS_POD" -n "$NAMESPACE" --timeout=120s

# Install WP-CLI in the running container (to user-writable location)
log_info "Installing WP-CLI in the WordPress container..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    # Create a local bin directory for www-data user
    mkdir -p /var/www/bin
    
    # Install WP-CLI to user-writable location
    curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /var/www/bin/wp
    
    # Create WP-CLI config
    cat > /var/www/html/wp-cli.yml << 'EOF'
path: /var/www/html
url: https://ethos.gray-beard.com
user: admin
core download:
  locale: en_US
  version: latest
  force: false
EOF
    
    echo 'WP-CLI installed to /var/www/bin/wp'
    echo 'WP-CLI installation completed'
"

# Test WP-CLI installation
log_info "Testing WP-CLI installation..."
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --info --allow-root >/dev/null 2>&1; then
    log_success "✅ WP-CLI is installed and working!"
    
    # Show WP-CLI info
    echo ""
    log_info "WP-CLI Information:"
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --info --allow-root
    
else
    log_error "❌ WP-CLI installation failed"
fi

echo ""
log_info "🔍 Verification Commands:"
echo "# Test WP-CLI:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp --info --allow-root"
echo ""
echo "# Check WordPress status:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp core is-installed --allow-root"
echo ""
echo "# List WordPress options:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp option list --allow-root"

echo ""
log_info "📝 Next Steps:"
echo "1. Test WordPress site: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
echo "2. Run URL update script: ./update-wordpress-urls-advanced.sh"
echo "3. Access WordPress admin: https://ethos.gray-beard.com/wp-admin"

echo ""
log_success "🎉 WordPress with WP-CLI deployment completed!"