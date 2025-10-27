#!/bin/bash

# EthosEnv Backup Script
# Creates SQL dump of MySQL database and tar.gz archive of WordPress files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="ethosenv"
MYSQL_POD="mysql-5c896dd94c-x8z6z"
WORDPRESS_POD="wordpress-85d6f7bfc4-4bhgw"
BACKUP_DIR="./backups/ethosenv"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo -e "${BLUE}EthosEnv Backup Script${NC}"
echo -e "${BLUE}=====================${NC}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to get database credentials
get_db_credentials() {
    echo -e "${YELLOW}Getting database credentials...${NC}"
    
    # Try to get credentials from WordPress pod environment
    DB_NAME=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -- printenv WORDPRESS_DB_NAME 2>/dev/null || echo "wordpress")
    DB_USER=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -- printenv WORDPRESS_DB_USER 2>/dev/null || echo "wordpress")
    
    # Try to get password from environment or secret
    DB_PASSWORD=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -- printenv WORDPRESS_DB_PASSWORD 2>/dev/null || echo "")
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${YELLOW}Trying to get password from secrets...${NC}"
        # Look for common secret names
        for secret in mysql-secret wordpress-secret mysql-root-password; do
            DB_PASSWORD=$(kubectl get secret $secret -n $NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [ -n "$DB_PASSWORD" ]; then
                break
            fi
            DB_PASSWORD=$(kubectl get secret $secret -n $NAMESPACE -o jsonpath='{.data.mysql-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [ -n "$DB_PASSWORD" ]; then
                break
            fi
            DB_PASSWORD=$(kubectl get secret $secret -n $NAMESPACE -o jsonpath='{.data.mysql-root-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [ -n "$DB_PASSWORD" ]; then
                DB_USER="root"
                break
            fi
        done
    fi
    
    echo -e "${GREEN}Database: $DB_NAME${NC}"
    echo -e "${GREEN}User: $DB_USER${NC}"
    echo -e "${GREEN}Password: ${DB_PASSWORD:+[FOUND]}${DB_PASSWORD:-[NOT FOUND]}${NC}"
}

# Function to backup MySQL database
backup_database() {
    echo -e "${YELLOW}Creating MySQL database backup...${NC}"
    
    local backup_file="$BACKUP_DIR/ethosenv_database_$TIMESTAMP.sql"
    
    if [ -n "$DB_PASSWORD" ]; then
        # Create SQL dump
        kubectl exec -n $NAMESPACE $MYSQL_POD -- mysqldump \
            -u "$DB_USER" \
            -p"$DB_PASSWORD" \
            --single-transaction \
            --routines \
            --triggers \
            --add-drop-table \
            --add-locks \
            --create-options \
            --disable-keys \
            --extended-insert \
            --quick \
            --set-charset \
            "$DB_NAME" > "$backup_file"
        
        if [ -s "$backup_file" ]; then
            echo -e "${GREEN}✓ Database backup created: $backup_file${NC}"
            echo -e "${BLUE}Size: $(du -h "$backup_file" | cut -f1)${NC}"
        else
            echo -e "${RED}✗ Database backup failed or is empty${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Cannot backup database: No password found${NC}"
        echo -e "${YELLOW}Available secrets in namespace:${NC}"
        kubectl get secrets -n $NAMESPACE
        return 1
    fi
}

# Function to backup WordPress files
backup_wordpress_files() {
    echo -e "${YELLOW}Creating WordPress files backup...${NC}"
    
    local backup_file="$BACKUP_DIR/ethosenv_wordpress_$TIMESTAMP.tar.gz"
    
    # Create tar.gz archive of WordPress files
    kubectl exec -n $NAMESPACE $WORDPRESS_POD -- tar -czf - /var/www/html > "$backup_file"
    
    if [ -s "$backup_file" ]; then
        echo -e "${GREEN}✓ WordPress files backup created: $backup_file${NC}"
        echo -e "${BLUE}Size: $(du -h "$backup_file" | cut -f1)${NC}"
        
        # List contents summary
        echo -e "${BLUE}Archive contents:${NC}"
        kubectl exec -n $NAMESPACE $WORDPRESS_POD -- find /var/www/html -maxdepth 2 -type d | head -10
    else
        echo -e "${RED}✗ WordPress files backup failed or is empty${NC}"
        return 1
    fi
}

# Function to create backup manifest
create_backup_manifest() {
    local manifest_file="$BACKUP_DIR/ethosenv_backup_manifest_$TIMESTAMP.txt"
    
    cat > "$manifest_file" << EOF
EthosEnv Backup Manifest
========================
Date: $(date)
Namespace: $NAMESPACE
Timestamp: $TIMESTAMP

Database Information:
- Database Name: $DB_NAME
- Database User: $DB_USER
- MySQL Pod: $MYSQL_POD

WordPress Information:
- WordPress Pod: $WORDPRESS_POD
- WordPress Path: /var/www/html

Backup Files:
- Database: ethosenv_database_$TIMESTAMP.sql
- WordPress Files: ethosenv_wordpress_$TIMESTAMP.tar.gz

Kubernetes Resources:
$(kubectl get all -n $NAMESPACE)

Persistent Volumes:
$(kubectl get pvc -n $NAMESPACE)

Pod Details:
WordPress Pod:
$(kubectl describe pod $WORDPRESS_POD -n $NAMESPACE | head -20)

MySQL Pod:
$(kubectl describe pod $MYSQL_POD -n $NAMESPACE | head -20)
EOF

    echo -e "${GREEN}✓ Backup manifest created: $manifest_file${NC}"
}

# Function to verify backups
verify_backups() {
    echo -e "${YELLOW}Verifying backups...${NC}"
    
    local db_backup="$BACKUP_DIR/ethosenv_database_$TIMESTAMP.sql"
    local wp_backup="$BACKUP_DIR/ethosenv_wordpress_$TIMESTAMP.tar.gz"
    
    # Verify database backup
    if [ -f "$db_backup" ] && [ -s "$db_backup" ]; then
        local db_size=$(du -h "$db_backup" | cut -f1)
        local db_lines=$(wc -l < "$db_backup")
        echo -e "${GREEN}✓ Database backup verified: $db_size, $db_lines lines${NC}"
        
        # Check for common WordPress tables
        if grep -q "wp_posts\|wp_users\|wp_options" "$db_backup"; then
            echo -e "${GREEN}✓ WordPress tables found in database backup${NC}"
        else
            echo -e "${YELLOW}⚠ WordPress tables not detected (might be using different prefix)${NC}"
        fi
    else
        echo -e "${RED}✗ Database backup verification failed${NC}"
    fi
    
    # Verify WordPress files backup
    if [ -f "$wp_backup" ] && [ -s "$wp_backup" ]; then
        local wp_size=$(du -h "$wp_backup" | cut -f1)
        echo -e "${GREEN}✓ WordPress files backup verified: $wp_size${NC}"
        
        # Test archive integrity
        if gzip -t "$wp_backup" 2>/dev/null; then
            echo -e "${GREEN}✓ Archive integrity verified${NC}"
        else
            echo -e "${RED}✗ Archive integrity check failed${NC}"
        fi
    else
        echo -e "${RED}✗ WordPress files backup verification failed${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Starting EthosEnv backup process...${NC}"
    echo -e "${BLUE}Backup directory: $BACKUP_DIR${NC}"
    echo -e "${BLUE}Timestamp: $TIMESTAMP${NC}"
    echo ""
    
    # Check if pods are running
    if ! kubectl get pod $MYSQL_POD -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${RED}✗ MySQL pod $MYSQL_POD not found or not running${NC}"
        exit 1
    fi
    
    if ! kubectl get pod $WORDPRESS_POD -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${RED}✗ WordPress pod $WORDPRESS_POD not found or not running${NC}"
        exit 1
    fi
    
    # Get database credentials
    get_db_credentials
    echo ""
    
    # Perform backups
    backup_database
    echo ""
    
    backup_wordpress_files
    echo ""
    
    # Create manifest
    create_backup_manifest
    echo ""
    
    # Verify backups
    verify_backups
    echo ""
    
    # Summary
    echo -e "${GREEN}EthosEnv backup completed!${NC}"
    echo -e "${BLUE}Backup files location: $BACKUP_DIR${NC}"
    echo ""
    echo -e "${YELLOW}Backup files created:${NC}"
    ls -lh "$BACKUP_DIR"/*"$TIMESTAMP"*
    echo ""
    echo -e "${YELLOW}Total backup size:${NC}"
    du -sh "$BACKUP_DIR"
}

# Run main function
main "$@"


