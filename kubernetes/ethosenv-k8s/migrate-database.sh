#!/bin/bash

# Migrate WordPress Database to Kubernetes
# This script helps migrate the existing WordPress database to the Kubernetes MySQL instance

set -euo pipefail

NAMESPACE="ethosenv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="../ethosenv"

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

echo "🗄️ WordPress Database Migration to Kubernetes..."

# Check if MySQL pod is running
MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MYSQL_POD" ]; then
    log_error "MySQL pod not found. Please deploy WordPress first."
    exit 1
fi

log_info "Found MySQL pod: $MYSQL_POD"

# Check if pod is ready
if ! kubectl wait --for=condition=ready pod/"$MYSQL_POD" -n "$NAMESPACE" --timeout=60s; then
    log_error "MySQL pod is not ready"
    exit 1
fi

# Function to create database backup from existing Docker setup
create_backup() {
    log_info "Creating database backup from existing setup..."
    
    if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
        log_info "Found Docker Compose setup. Creating backup..."
        cd "$BACKUP_DIR"
        
        # Check if Docker containers are running
        if docker-compose ps | grep -q "wordpress_mysql"; then
            log_info "Creating database dump..."
            docker-compose exec -T mysql mysqldump -u wordpress -pwordpress_password wordpress > wordpress_backup.sql
            log_success "Database backup created: wordpress_backup.sql"
        else
            log_warning "Docker containers are not running. Please start them first or provide a manual backup."
            log_info "You can create a backup manually by running:"
            echo "  cd $BACKUP_DIR"
            echo "  docker-compose up -d"
            echo "  docker-compose exec mysql mysqldump -u wordpress -pwordpress_password wordpress > wordpress_backup.sql"
            return 1
        fi
    else
        log_warning "No Docker Compose setup found. Please provide a database backup file."
        log_info "Place your database backup as 'wordpress_backup.sql' in the $BACKUP_DIR directory"
        return 1
    fi
}

# Function to restore database to Kubernetes
restore_database() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_info "Copying database backup to MySQL pod..."
    kubectl cp "$backup_file" "$NAMESPACE/$MYSQL_POD:/tmp/wordpress_backup.sql"
    
    log_info "Restoring database..."
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- bash -c "
        mysql -u root -proot_password wordpress < /tmp/wordpress_backup.sql
        rm -f /tmp/wordpress_backup.sql
    "
    
    log_success "Database restored successfully!"
}

# Function to update WordPress URLs in database
update_urls() {
    local old_url="$1"
    local new_url="$2"
    
    log_info "Updating WordPress URLs from $old_url to $new_url..."
    
    kubectl exec -n "$NAMESPACE" "$MYSQL_POD" -- mysql -u root -proot_password wordpress -e "
        UPDATE wp_options SET option_value = replace(option_value, '$old_url', '$new_url') WHERE option_name = 'home';
        UPDATE wp_options SET option_value = replace(option_value, '$old_url', '$new_url') WHERE option_name = 'siteurl';
        UPDATE wp_posts SET post_content = replace(post_content, '$old_url', '$new_url');
        UPDATE wp_postmeta SET meta_value = replace(meta_value, '$old_url', '$new_url');
        UPDATE wp_comments SET comment_content = replace(comment_content, '$old_url', '$new_url');
    "
    
    log_success "URLs updated successfully!"
}

# Main execution
case "${1:-}" in
    "backup")
        create_backup
        ;;
    "restore")
        backup_file="${2:-$BACKUP_DIR/wordpress_backup.sql}"
        restore_database "$backup_file"
        ;;
    "update-urls")
        old_url="${2:-http://localhost:8080}"
        new_url="${3:-http://wordpress.local}"
        update_urls "$old_url" "$new_url"
        ;;
    "full-migration")
        log_info "Performing full database migration..."
        create_backup
        restore_database "$BACKUP_DIR/wordpress_backup.sql"
        update_urls "http://localhost:8080" "http://wordpress.local"
        ;;
    *)
        echo "Usage: $0 {backup|restore [backup_file]|update-urls [old_url] [new_url]|full-migration}"
        echo ""
        echo "Commands:"
        echo "  backup           - Create backup from existing Docker setup"
        echo "  restore [file]   - Restore database from backup file"
        echo "  update-urls      - Update WordPress URLs in database"
        echo "  full-migration   - Perform complete migration (backup + restore + update URLs)"
        echo ""
        echo "Examples:"
        echo "  $0 backup"
        echo "  $0 restore /path/to/backup.sql"
        echo "  $0 update-urls http://localhost:8080 http://wordpress.local"
        echo "  $0 full-migration"
        exit 1
        ;;
esac

echo ""
log_info "📝 Next Steps:"
echo "1. Verify the database content: kubectl exec -n $NAMESPACE $MYSQL_POD -- mysql -u root -proot_password wordpress -e 'SHOW TABLES;'"
echo "2. Check WordPress site functionality"
echo "3. Update any remaining hardcoded URLs or paths"

echo ""
log_warning "⚠️  Important Notes:"
echo "1. Make sure WordPress files are also migrated using migrate-wordpress-content.sh"
echo "2. Test all functionality after migration"
echo "3. Consider setting up regular database backups in Kubernetes"