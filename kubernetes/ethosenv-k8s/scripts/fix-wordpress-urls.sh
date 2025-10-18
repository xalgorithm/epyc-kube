#!/bin/bash

# Fix WordPress URLs - Remove port 8080 and set correct domain

set -euo pipefail

NAMESPACE="ethosenv"
CORRECT_URL="https://ethos.gray-beard.com"

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

echo "🔧 WordPress URL Fixer"
echo "📝 Setting all URLs to: $CORRECT_URL"
echo ""

# Find MySQL pod
MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MYSQL_POD" ]; then
    log_error "MySQL pod not found"
    exit 1
fi

log_info "MySQL pod: $MYSQL_POD"

# Get credentials
DB_USER=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_USER}' | base64 -d)
DB_PASSWORD=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)
DB_NAME=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_DATABASE}' | base64 -d)

# Function to execute MySQL command
execute_mysql() {
    local query="$1"
    local description="$2"
    
    log_info "$description"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$query"
}

# Show current URLs
log_info "Current WordPress URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null

echo ""
log_info "🔄 Fixing WordPress URLs..."

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
    log_info "Fixing URLs: $OLD_URL → $CORRECT_URL"
    
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
log_info "Setting core WordPress URLs directly..."
execute_mysql "UPDATE wp_options SET option_value = '$CORRECT_URL' WHERE option_name = 'home';" "Setting home URL"
execute_mysql "UPDATE wp_options SET option_value = '$CORRECT_URL' WHERE option_name = 'siteurl';" "Setting site URL"

# Clear WordPress caches
log_info "Clearing WordPress caches..."
execute_mysql "DELETE FROM wp_options WHERE option_name LIKE '_transient_%' OR option_name LIKE '_site_transient_%';" "Clearing transients"

echo ""
log_success "✅ URL fixes completed!"

# Show updated URLs
log_info "Updated WordPress URLs:"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" 2>/dev/null

# Check for any remaining problematic URLs
echo ""
log_info "Checking for any remaining problematic URLs..."

REMAINING_8080=$(kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT COUNT(*) FROM wp_options WHERE option_value LIKE '%:8080%';" --skip-column-names 2>/dev/null)
REMAINING_LOCALHOST=$(kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT COUNT(*) FROM wp_options WHERE option_value LIKE '%localhost%';" --skip-column-names 2>/dev/null)

if [ "$REMAINING_8080" -gt 0 ]; then
    log_warning "Found $REMAINING_8080 options still containing :8080"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%:8080%' LIMIT 5;" 2>/dev/null
fi

if [ "$REMAINING_LOCALHOST" -gt 0 ]; then
    log_warning "Found $REMAINING_LOCALHOST options still containing localhost"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%localhost%' LIMIT 5;" 2>/dev/null
fi

if [ "$REMAINING_8080" -eq 0 ] && [ "$REMAINING_LOCALHOST" -eq 0 ]; then
    log_success "✅ No problematic URLs found!"
fi

echo ""
log_info "📝 Next Steps:"
echo "1. Test the site: $CORRECT_URL"
echo "2. Check WordPress admin: $CORRECT_URL/wp-admin"
echo "3. Clear any plugin caches if installed"

echo ""
log_success "🎉 WordPress URL fix completed!"
echo "Your site should now be accessible at: $CORRECT_URL"