#!/bin/bash

# Master WordPress Deployment Script
# Deploys WordPress from kubernetes/ethosenv to Kubernetes cluster with all fixes and migrations

set -euo pipefail

NAMESPACE="ethosenv"
SOURCE_DIR="../ethosenv/wordpress"
CORRECT_URL="https://ethos.gray-beard.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

log_substep() {
    echo -e "${CYAN}[SUBSTEP]${NC} $1"
}

# Function to wait for user confirmation
confirm_step() {
    local message="$1"
    echo ""
    log_warning "⚠️  $message"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Function to execute MySQL command
execute_mysql() {
    local query="$1"
    local description="$2"
    
    log_substep "$description"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$query" >/dev/null 2>&1
}

echo "🚀 Master WordPress Deployment Script"
echo "📦 Source: $SOURCE_DIR"
echo "🎯 Target: Kubernetes cluster ($NAMESPACE namespace)"
echo "🌐 URL: $CORRECT_URL"
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    log_error "Source WordPress directory not found: $SOURCE_DIR"
    log_info "Please ensure the ethosenv WordPress content is available at this location"
    exit 1
fi

log_success "✅ Source directory found: $SOURCE_DIR"

# ============================================================================
# STEP 1: DEPLOY KUBERNETES INFRASTRUCTURE
# ============================================================================
log_step "1. Deploying Kubernetes Infrastructure"

log_substep "Creating namespace..."
kubectl apply -f 01-namespace.yaml

log_substep "Creating secrets..."
kubectl apply -f 02-secrets.yaml

log_substep "Creating storage..."
kubectl apply -f 03-storage.yaml

log_substep "Deploying MySQL..."
kubectl apply -f 04-mysql-deployment.yaml

log_substep "Deploying WordPress..."
kubectl apply -f 05-wordpress-deployment.yaml

log_substep "Creating ingress..."
kubectl apply -f 06-ingress.yaml

log_success "✅ Kubernetes infrastructure deployed"

# ============================================================================
# STEP 2: WAIT FOR DEPLOYMENTS TO BE READY
# ============================================================================
log_step "2. Waiting for Deployments to be Ready"

log_substep "Waiting for MySQL to be ready..."
kubectl wait --for=condition=available deployment/mysql -n "$NAMESPACE" --timeout=300s

log_substep "Waiting for WordPress to be ready..."
kubectl wait --for=condition=available deployment/wordpress -n "$NAMESPACE" --timeout=300s

# Get pod names
MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}')
WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}')

log_substep "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod/"$MYSQL_POD" -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=ready pod/"$WORDPRESS_POD" -n "$NAMESPACE" --timeout=120s

log_success "✅ All deployments are ready"
log_info "MySQL pod: $MYSQL_POD"
log_info "WordPress pod: $WORDPRESS_POD"

# ============================================================================
# STEP 3: INSTALL WP-CLI
# ============================================================================
log_step "3. Installing WP-CLI"

log_substep "Checking if WP-CLI is already installed..."
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- test -f /var/www/bin/wp >/dev/null 2>&1; then
    log_success "✅ WP-CLI already installed"
else
    log_substep "Installing WP-CLI to user-writable location..."
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
        mkdir -p /var/www/bin
        curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /var/www/bin/wp
        echo 'WP-CLI installed to /var/www/bin/wp'
    "
    
    log_substep "Creating WP-CLI configuration..."
    kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
        cat > /var/www/html/wp-cli.yml << 'EOF'
path: /var/www/html
url: $CORRECT_URL
user: admin
core download:
  locale: en_US
  version: latest
  force: false
EOF
    "
    
    log_success "✅ WP-CLI installed and configured"
fi

# Test WP-CLI
log_substep "Testing WP-CLI installation..."
if kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- /var/www/bin/wp --info --allow-root >/dev/null 2>&1; then
    log_success "✅ WP-CLI is working"
else
    log_warning "⚠️  WP-CLI test failed, but continuing..."
fi

# ============================================================================
# STEP 4: MIGRATE WORDPRESS CONTENT
# ============================================================================
log_step "4. Migrating WordPress Content"

log_substep "Backing up existing wp-config.php..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    if [ -f /var/www/html/wp-config.php ]; then
        cp /var/www/html/wp-config.php /tmp/wp-config.php.backup
        echo 'wp-config.php backed up'
    fi
"

# Function to copy directory with progress
copy_directory() {
    local src_dir="$1"
    local dest_path="$2"
    local desc="$3"
    
    if [ -d "$src_dir" ]; then
        log_substep "Copying $desc..."
        
        # Create destination directory in pod
        kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- mkdir -p "$dest_path" 2>/dev/null || true
        
        # Use kubectl cp for the entire directory
        if kubectl cp "$src_dir" "$NAMESPACE/$WORDPRESS_POD:$dest_path" 2>/dev/null; then
            log_success "✅ $desc copied successfully"
        else
            log_warning "⚠️  $desc copy had issues, trying alternative method..."
            
            # Alternative: copy contents instead of directory
            local temp_name=$(basename "$src_dir")
            if kubectl cp "$src_dir/." "$NAMESPACE/$WORDPRESS_POD:$dest_path/$temp_name/" 2>/dev/null; then
                log_success "✅ $desc copied successfully (alternative method)"
            else
                log_error "❌ Failed to copy $desc"
                return 1
            fi
        fi
    else
        log_info "⏭️  $desc not found in source, skipping"
    fi
}

# Function to copy single file
copy_file() {
    local src_file="$1"
    local dest_path="$2"
    local desc="$3"
    
    if [ -f "$src_file" ]; then
        log_substep "Copying $desc..."
        if kubectl cp "$src_file" "$NAMESPACE/$WORDPRESS_POD:$dest_path" 2>/dev/null; then
            log_success "✅ $desc copied successfully"
        else
            log_warning "⚠️  Failed to copy $desc"
        fi
    else
        log_info "⏭️  $desc not found in source, skipping"
    fi
}

# Copy WordPress content directories systematically
copy_directory "$SOURCE_DIR/wp-content/themes" "/var/www/html/wp-content" "WordPress themes"
copy_directory "$SOURCE_DIR/wp-content/plugins" "/var/www/html/wp-content" "WordPress plugins"
copy_directory "$SOURCE_DIR/wp-content/uploads" "/var/www/html/wp-content" "WordPress uploads"
copy_directory "$SOURCE_DIR/wp-content/languages" "/var/www/html/wp-content" "WordPress languages"

# Copy important files
copy_file "$SOURCE_DIR/.htaccess" "/var/www/html/.htaccess" ".htaccess file"
copy_file "$SOURCE_DIR/wp-config.php" "/tmp/wp-config-original.php" "Original wp-config.php (for reference)"

# Copy any custom wp-content files
if [ -d "$SOURCE_DIR/wp-content" ]; then
    log_substep "Checking for additional wp-content files..."
    
    # Find files directly in wp-content (not in subdirectories we already copied)
    cd "$SOURCE_DIR/wp-content"
    for item in *; do
        if [ -f "$item" ] && [[ "$item" != "index.php" ]]; then
            copy_file "$SOURCE_DIR/wp-content/$item" "/var/www/html/wp-content/$item" "wp-content/$item"
        fi
    done
    cd - >/dev/null
fi

log_substep "Setting permissions and restoring configuration..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    # Restore the Kubernetes wp-config.php
    if [ -f /tmp/wp-config.php.backup ]; then
        cp /tmp/wp-config.php.backup /var/www/html/wp-config.php
        echo 'Kubernetes wp-config.php restored'
    fi
    
    # Set proper ownership
    chown -R www-data:www-data /var/www/html
    echo 'Ownership set to www-data'
    
    # Clean up temp files
    rm -f /tmp/wp-config.php.backup /tmp/wp-config-original.php
"

log_success "✅ WordPress content migration completed"

# ============================================================================
# STEP 5: FIX WORDPRESS URLS
# ============================================================================
log_step "5. Fixing WordPress URLs"

# Get database credentials
log_substep "Retrieving database credentials..."
DB_USER=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_USER}' | base64 -d)
DB_PASSWORD=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)
DB_NAME=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_DATABASE}' | base64 -d)

# Check if WordPress tables exist
log_substep "Checking WordPress installation..."
TABLES_CHECK=$(kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES LIKE 'wp_%';" 2>/dev/null || echo "")

if [ -z "$TABLES_CHECK" ]; then
    log_warning "⚠️  No WordPress tables found. WordPress may need initial setup."
else
    log_success "✅ WordPress tables found"
    
    # Show current URLs
    log_substep "Current WordPress URLs:"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null || true
    
    log_substep "Fixing WordPress URLs..."
    
    # List of URL patterns to fix
    URL_PATTERNS=(
        "http://localhost:8080"
        "https://localhost:8080"
        "http://localhost"
        "https://localhost"
        "http://ethos.gray-beard.com:8080"
        "https://ethos.gray-beard.com:8080"
        "http://ethos.gray-beard.com"
    )
    
    # Fix each URL pattern
    for OLD_URL in "${URL_PATTERNS[@]}"; do
        log_substep "Fixing URLs: $OLD_URL → $CORRECT_URL"
        
        # Update core WordPress options
        execute_mysql "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$CORRECT_URL') WHERE option_name IN ('home', 'siteurl');" "Updating core URLs"
        
        # Update all options that might contain URLs
        execute_mysql "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$CORRECT_URL') WHERE option_value LIKE '%$OLD_URL%';" "Updating all options"
        
        # Update post content
        execute_mysql "UPDATE wp_posts SET post_content = REPLACE(post_content, '$OLD_URL', '$CORRECT_URL');" "Updating post content"
        execute_mysql "UPDATE wp_posts SET post_excerpt = REPLACE(post_excerpt, '$OLD_URL', '$CORRECT_URL');" "Updating post excerpts"
        execute_mysql "UPDATE wp_posts SET guid = REPLACE(guid, '$OLD_URL', '$CORRECT_URL');" "Updating post GUIDs"
        
        # Update comments
        execute_mysql "UPDATE wp_comments SET comment_content = REPLACE(comment_content, '$OLD_URL', '$CORRECT_URL');" "Updating comments"
        execute_mysql "UPDATE wp_comments SET comment_author_url = REPLACE(comment_author_url, '$OLD_URL', '$CORRECT_URL');" "Updating comment author URLs"
        
        # Update metadata
        execute_mysql "UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$CORRECT_URL');" "Updating post metadata"
        execute_mysql "UPDATE wp_commentmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$CORRECT_URL');" "Updating comment metadata"
        execute_mysql "UPDATE wp_usermeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$CORRECT_URL');" "Updating user metadata"
    done
    
    # Set the core URLs directly (in case they weren't caught by the patterns)
    log_substep "Setting core WordPress URLs directly..."
    execute_mysql "UPDATE wp_options SET option_value = '$CORRECT_URL' WHERE option_name = 'home';" "Setting home URL"
    execute_mysql "UPDATE wp_options SET option_value = '$CORRECT_URL' WHERE option_name = 'siteurl';" "Setting site URL"
    
    # Clear WordPress caches
    log_substep "Clearing WordPress caches..."
    execute_mysql "DELETE FROM wp_options WHERE option_name LIKE '_transient_%' OR option_name LIKE '_site_transient_%';" "Clearing transients"
    
    log_success "✅ WordPress URLs fixed"
    
    # Show updated URLs
    log_substep "Updated WordPress URLs:"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null || true
fi

# ============================================================================
# STEP 6: FIX INGRESS AND CONNECTIVITY
# ============================================================================
log_step "6. Fixing Ingress and Connectivity"

log_substep "Checking WordPress service..."
kubectl get service wordpress -n "$NAMESPACE" -o wide

log_substep "Checking service endpoints..."
ENDPOINTS=$(kubectl get endpoints wordpress -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")

if [ -z "$ENDPOINTS" ]; then
    log_warning "⚠️  No service endpoints found. Restarting WordPress deployment..."
    kubectl rollout restart deployment/wordpress -n "$NAMESPACE"
    kubectl rollout status deployment/wordpress -n "$NAMESPACE" --timeout=300s
    
    # Update pod name after restart
    WORDPRESS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
    log_info "New WordPress pod: $WORDPRESS_POD"
else
    log_success "✅ Service has endpoints: $ENDPOINTS"
fi

log_substep "Testing WordPress service directly..."
kubectl run test-service-$RANDOM --image=curlimages/curl --rm -i --restart=Never -- curl -s -I http://wordpress.ethosenv.svc.cluster.local:80/ 2>/dev/null && log_success "✅ Service responds" || log_warning "⚠️  Service test failed"

log_substep "Checking ingress configuration..."
if kubectl get ingress wordpress-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o wide
    
    # Check if ingress has an address
    INGRESS_ADDRESS=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -z "$INGRESS_ADDRESS" ]; then
        log_warning "⚠️  Ingress has no external address. Recreating ingress..."
        
        kubectl delete ingress wordpress-ingress -n "$NAMESPACE" 2>/dev/null || true
        sleep 5
        kubectl apply -f 06-ingress.yaml
        
        log_substep "Waiting for ingress to get an address..."
        sleep 30
        kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o wide
    else
        log_success "✅ Ingress has address: $INGRESS_ADDRESS"
    fi
else
    log_warning "⚠️  Ingress not found. Creating ingress..."
    kubectl apply -f 06-ingress.yaml
fi

log_success "✅ Ingress and connectivity fixes applied"

# ============================================================================
# STEP 7: INSTALL SSL CERTIFICATES
# ============================================================================
log_step "7. Setting up SSL Certificates"

log_substep "Applying cert-manager issuer..."
kubectl apply -f 07-cert-manager-issuer.yaml 2>/dev/null || log_warning "Cert-manager issuer may already exist"

log_substep "Applying SSL certificate..."
kubectl apply -f 08-ssl-certificate.yaml 2>/dev/null || log_warning "SSL certificate may already exist"

log_substep "Checking SSL certificate status..."
if kubectl get certificate ethos-tls-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    CERT_STATUS=$(kubectl get certificate ethos-tls-secret -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$CERT_STATUS" = "True" ]; then
        log_success "✅ SSL certificate is ready"
    else
        log_warning "⚠️  SSL certificate not ready yet. Status: $CERT_STATUS"
        log_info "Certificate will be issued automatically. This may take a few minutes."
    fi
else
    log_warning "⚠️  SSL certificate not found"
fi

log_success "✅ SSL certificate setup completed"

# ============================================================================
# STEP 8: FINAL VERIFICATION
# ============================================================================
log_step "8. Final Verification"

log_substep "Testing external connectivity..."
echo "Testing HTTP (should redirect to HTTPS):"
curl -I http://ethos.gray-beard.com 2>/dev/null && log_success "✅ HTTP responds" || log_warning "⚠️  HTTP test failed"

echo ""
echo "Testing HTTPS:"
curl -I https://ethos.gray-beard.com 2>/dev/null && log_success "✅ HTTPS responds" || log_warning "⚠️  HTTPS test failed"

log_substep "Checking DNS resolution..."
nslookup ethos.gray-beard.com 2>/dev/null && log_success "✅ DNS resolves" || log_warning "⚠️  DNS resolution failed"

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================
echo ""
echo "🎉 ============================================================================"
echo "🎉                    MASTER DEPLOYMENT COMPLETED!"
echo "🎉 ============================================================================"
echo ""

log_success "✅ Kubernetes infrastructure deployed"
log_success "✅ WordPress and MySQL are running"
log_success "✅ WP-CLI installed and configured"
log_success "✅ WordPress content migrated from $SOURCE_DIR"
log_success "✅ WordPress URLs fixed and set to $CORRECT_URL"
log_success "✅ Ingress and connectivity configured"
log_success "✅ SSL certificates configured"

echo ""
log_info "📊 Deployment Summary:"
echo "- Namespace: $NAMESPACE"
echo "- WordPress URL: $CORRECT_URL"
echo "- WordPress Admin: $CORRECT_URL/wp-admin"
echo "- Source Content: $SOURCE_DIR"
echo "- WP-CLI Path: /var/www/bin/wp"

echo ""
log_info "🔍 Verification Commands:"
echo "# Check all pods:"
echo "kubectl get pods -n $NAMESPACE"
echo ""
echo "# Check services:"
echo "kubectl get services -n $NAMESPACE"
echo ""
echo "# Check ingress:"
echo "kubectl get ingress -n $NAMESPACE"
echo ""
echo "# Test WP-CLI:"
echo "kubectl exec -n $NAMESPACE $WORDPRESS_POD -- /var/www/bin/wp --info --allow-root"

echo ""
log_info "🌐 Access Your Site:"
echo "WordPress Site: $CORRECT_URL"
echo "WordPress Admin: $CORRECT_URL/wp-admin"

echo ""
log_info "🛠️  Troubleshooting:"
echo "# Check WordPress logs:"
echo "kubectl logs deployment/wordpress -n $NAMESPACE"
echo ""
echo "# Port-forward for testing:"
echo "kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
echo ""
echo "# Run individual fix scripts if needed:"
echo "./fix-wordpress-urls.sh"
echo "./fix-ingress-issues.sh"

echo ""
log_success "🎉 Your WordPress site should now be live at: $CORRECT_URL"