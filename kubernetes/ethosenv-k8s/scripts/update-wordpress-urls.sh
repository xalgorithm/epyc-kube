#!/bin/bash

# WordPress URL Update Script
# Updates WordPress URLs from http://localhost to https://ethos.gray-beard.com in MySQL database

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

echo "🔄 WordPress URL Update Script"
echo "📝 Updating URLs from: $OLD_URL"
echo "📝 Updating URLs to: $NEW_URL"
echo ""

# Check if MySQL pod is running
MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MYSQL_POD" ]; then
    log_error "MySQL pod not found. Please deploy MySQL first."
    exit 1
fi

log_info "Found MySQL pod: $MYSQL_POD"

# Check if pod is ready
if ! kubectl wait --for=condition=ready pod/"$MYSQL_POD" -n "$NAMESPACE" --timeout=60s; then
    log_error "MySQL pod is not ready"
    exit 1
fi

# Get database credentials from secrets
log_info "Retrieving database credentials..."
DB_NAME=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_DATABASE}' | base64 -d)
DB_USER=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_USER}' | base64 -d)
DB_PASSWORD=$(kubectl get secret mysql-secrets -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)

log_info "Database: $DB_NAME"
log_info "User: $DB_USER"

# Function to execute MySQL command
execute_mysql() {
    local query="$1"
    local description="$2"
    
    log_info "$description"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$query"
}

# Function to execute MySQL command and get result
execute_mysql_result() {
    local query="$1"
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$query" 2>/dev/null
}

# Check if WordPress tables exist
log_info "Checking WordPress installation..."
TABLES_CHECK=$(execute_mysql_result "SHOW TABLES LIKE 'wp_%';" || echo "")

if [ -z "$TABLES_CHECK" ]; then
    log_error "No WordPress tables found. Please install WordPress first."
    exit 1
fi

log_success "WordPress tables found"

# Create backup before making changes
log_info "Creating database backup..."
BACKUP_FILE="/tmp/wordpress_backup_$(date +%Y%m%d_%H%M%S).sql"
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysqldump -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null || {
    log_warning "Backup creation failed, but continuing with URL updates"
}

# Show current URLs before update
log_info "Current WordPress URLs:"
execute_mysql_result "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" || true

echo ""
log_info "🔄 Starting URL updates..."

# Update WordPress core options
log_info "1. Updating WordPress core options (wp_options table)..."
execute_mysql "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$NEW_URL') WHERE option_name = 'home';" "Updating home URL"
execute_mysql "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$NEW_URL') WHERE option_name = 'siteurl';" "Updating site URL"

# Update post content
log_info "2. Updating post content (wp_posts table)..."
execute_mysql "UPDATE wp_posts SET post_content = REPLACE(post_content, '$OLD_URL', '$NEW_URL');" "Updating post content URLs"
execute_mysql "UPDATE wp_posts SET post_excerpt = REPLACE(post_excerpt, '$OLD_URL', '$NEW_URL');" "Updating post excerpt URLs"
execute_mysql "UPDATE wp_posts SET guid = REPLACE(guid, '$OLD_URL', '$NEW_URL');" "Updating post GUIDs"

# Update comments
log_info "3. Updating comments (wp_comments table)..."
execute_mysql "UPDATE wp_comments SET comment_content = REPLACE(comment_content, '$OLD_URL', '$NEW_URL');" "Updating comment content URLs"
execute_mysql "UPDATE wp_comments SET comment_author_url = REPLACE(comment_author_url, '$OLD_URL', '$NEW_URL');" "Updating comment author URLs"

# Update metadata
log_info "4. Updating metadata..."
execute_mysql "UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$NEW_URL');" "Updating post metadata URLs"
execute_mysql "UPDATE wp_commentmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$NEW_URL');" "Updating comment metadata URLs"
execute_mysql "UPDATE wp_usermeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$NEW_URL');" "Updating user metadata URLs"

# Update options that might contain serialized data
log_info "5. Updating theme and plugin options..."
execute_mysql "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$NEW_URL') WHERE option_value LIKE '%$OLD_URL%';" "Updating all options containing old URL"

# Handle serialized data (WordPress often stores serialized PHP data)
log_info "6. Handling serialized data..."
kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- bash -c "
mysql -u '$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' -e \"
UPDATE wp_options 
SET option_value = REPLACE(option_value, 's:${#OLD_URL}:\\\"$OLD_URL\\\";', 's:${#NEW_URL}:\\\"$NEW_URL\\\";') 
WHERE option_value LIKE '%s:${#OLD_URL}:\\\"$OLD_URL\\\"%';
\"
" 2>/dev/null || log_warning "Serialized data update may have had issues (this is often normal)"

# Update widget content
log_info "7. Updating widgets and customizer settings..."
execute_mysql "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$NEW_URL') WHERE option_name LIKE 'widget_%' OR option_name LIKE 'theme_mods_%';" "Updating widget and theme customizer URLs"

# Clear any caches
log_info "8. Clearing WordPress caches..."
execute_mysql "DELETE FROM wp_options WHERE option_name LIKE '_transient_%' OR option_name LIKE '_site_transient_%';" "Clearing WordPress transients/cache"

echo ""
log_success "✅ URL updates completed!"

# Show updated URLs
log_info "Updated WordPress URLs:"
execute_mysql_result "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');" || true

echo ""
log_info "📊 Update Summary:"
echo "- Core WordPress URLs (home, siteurl): ✅ Updated"
echo "- Post content and excerpts: ✅ Updated"
echo "- Post GUIDs: ✅ Updated"
echo "- Comments and author URLs: ✅ Updated"
echo "- Post, comment, and user metadata: ✅ Updated"
echo "- Theme and plugin options: ✅ Updated"
echo "- Serialized data: ✅ Attempted (may need manual review)"
echo "- Widgets and customizer: ✅ Updated"
echo "- WordPress caches: ✅ Cleared"

echo ""
log_info "🔍 Verification Commands:"
echo "# Check WordPress URLs:"
echo "kubectl exec -n $NAMESPACE $MYSQL_POD -- mysql -u $DB_USER -p'$DB_PASSWORD' $DB_NAME -e \"SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');\""
echo ""
echo "# Search for any remaining old URLs:"
echo "kubectl exec -n $NAMESPACE $MYSQL_POD -- mysql -u $DB_USER -p'$DB_PASSWORD' $DB_NAME -e \"SELECT 'wp_options' as table_name, option_name as field, option_value as value FROM wp_options WHERE option_value LIKE '%$OLD_URL%' UNION SELECT 'wp_posts', 'post_content', post_content FROM wp_posts WHERE post_content LIKE '%$OLD_URL%' LIMIT 10;\""

echo ""
log_info "📝 Next Steps:"
echo "1. Clear any WordPress caching plugins if installed"
echo "2. Update .htaccess rules if needed"
echo "3. Check WordPress admin dashboard for any remaining issues"
echo "4. Test the site at: $NEW_URL"
echo "5. Update any hardcoded URLs in theme files or plugins"

echo ""
log_warning "⚠️  Important Notes:"
echo "1. Some plugins may store URLs in custom tables - check plugin documentation"
echo "2. Serialized data updates may need manual verification for complex data structures"
echo "3. If using a caching plugin, clear all caches after this update"
echo "4. Consider using WordPress CLI (wp-cli) for more advanced serialized data handling"
echo "5. Backup created at: $BACKUP_FILE (if successful)"

if [ -f "$BACKUP_FILE" ]; then
    log_success "✅ Database backup available at: $BACKUP_FILE"
else
    log_warning "⚠️  No backup was created - consider creating one manually"
fi

echo ""
log_success "🎉 WordPress URL migration from $OLD_URL to $NEW_URL completed!"