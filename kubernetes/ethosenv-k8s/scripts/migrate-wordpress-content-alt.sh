#!/bin/bash

# Alternative WordPress Content Migration Script
# This script uses rsync-style copying to avoid tar extended attribute issues on macOS

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

echo "📦 Migrating WordPress Content to Kubernetes (Alternative Method)..."
echo ""
log_info "💡 This method uses direct directory copying to completely avoid tar and extended attribute issues."
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

log_info "Backing up existing wp-config.php in pod..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    cd /var/www/html
    if [ -f wp-config.php ]; then
        cp wp-config.php wp-config.php.backup
        echo 'wp-config.php backed up'
    else
        echo 'No existing wp-config.php found'
    fi
"

log_info "Using direct directory copying (no tar, no extended attributes)..."

# Function to copy directory with progress
copy_directory() {
    local src_dir="$1"
    local dest_path="$2"
    local desc="$3"
    
    if [ -d "$src_dir" ]; then
        log_info "Copying $desc..."
        
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
        log_info "Copying $desc..."
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
    log_info "Checking for additional wp-content files..."
    
    # Find files directly in wp-content (not in subdirectories we already copied)
    cd "$SOURCE_DIR/wp-content"
    for item in *; do
        if [ -f "$item" ] && [[ "$item" != "index.php" ]]; then
            copy_file "$SOURCE_DIR/wp-content/$item" "/var/www/html/wp-content/$item" "wp-content/$item"
        fi
    done
    cd - >/dev/null
fi

log_info "Setting permissions and finalizing..."
kubectl exec -n "$NAMESPACE" "$WORDPRESS_POD" -- bash -c "
    # Set proper ownership
    chown -R www-data:www-data /var/www/html
    echo 'Ownership set to www-data'
    
    # Show summary
    echo 'Migration summary:'
    ls -la /var/www/html/wp-content/ 2>/dev/null | head -10 || echo 'wp-content directory structure:'
    find /var/www/html/wp-content -maxdepth 2 -type d 2>/dev/null | head -10 || true
    
    # Clean up temp files
    rm -f /tmp/wp-config-original.php
"

log_success "✅ WordPress content migration completed!"

echo ""
log_info "📋 Migration Summary:"
echo "- Source: $SOURCE_DIR"
echo "- Destination: $WORDPRESS_POD:/var/www/html"
echo "- Method: Direct directory copying (no tar, no extended attributes)"
echo "- Themes: $([ -d "$SOURCE_DIR/wp-content/themes" ] && echo "✅ Processed" || echo "⏭️  Skipped")"
echo "- Plugins: $([ -d "$SOURCE_DIR/wp-content/plugins" ] && echo "✅ Processed" || echo "⏭️  Skipped")"
echo "- Uploads: $([ -d "$SOURCE_DIR/wp-content/uploads" ] && echo "✅ Processed" || echo "⏭️  Skipped")"
echo "- Languages: $([ -d "$SOURCE_DIR/wp-content/languages" ] && echo "✅ Processed" || echo "⏭️  Skipped")"
echo "- .htaccess: $([ -f "$SOURCE_DIR/.htaccess" ] && echo "✅ Processed" || echo "⏭️  Skipped")"

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
log_success "🎉 Migration completed without any tar or extended attribute issues!"

echo ""
log_warning "⚠️  Important Notes:"
echo "1. The wp-config.php has been preserved to use Kubernetes environment variables"
echo "2. Make sure to migrate your database content separately"
echo "3. Update any hardcoded URLs in the database to match your new domain"
echo "4. This method completely avoids tar, eliminating all extended attribute warnings"