#!/bin/bash

# EthosEnv Dynamic Backup Script
# Automatically detects pods and creates SQL dump + WordPress files backup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="ethosenv"
BACKUP_DIR="./backups/ethosenv"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo -e "${BLUE}EthosEnv Dynamic Backup Script${NC}"
echo -e "${BLUE}==============================${NC}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to get pod names dynamically
get_pod_names() {
    echo -e "${YELLOW}Detecting pods in namespace $NAMESPACE...${NC}"
    
    MYSQL_POD=$(kubectl get pods -n $NAMESPACE -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
                kubectl get pods -n $NAMESPACE | grep mysql | awk '{print $1}' | head -1 || echo "")
    
    WORDPRESS_POD=$(kubectl get pods -n $NAMESPACE -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
                    kubectl get pods -n $NAMESPACE | grep wordpress | awk '{print $1}' | head -1 || echo "")
    
    if [ -z "$MYSQL_POD" ]; then
        echo -e "${RED}✗ No MySQL pod found in namespace $NAMESPACE${NC}"
        exit 1
    fi
    
    if [ -z "$WORDPRESS_POD" ]; then
        echo -e "${RED}✗ No WordPress pod found in namespace $NAMESPACE${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ MySQL Pod: $MYSQL_POD${NC}"
    echo -e "${GREEN}✓ WordPress Pod: $WORDPRESS_POD${NC}"
}

# Function to get database credentials from secrets
get_db_credentials_from_secrets() {
    echo -e "${YELLOW}Getting database credentials from secrets...${NC}"
    
    # Try mysql-secrets first
    if kubectl get secret mysql-secrets -n $NAMESPACE >/dev/null 2>&1; then
        DB_NAME=$(kubectl get secret mysql-secrets -n $NAMESPACE -o jsonpath='{.data.database}' 2>/dev/null | base64 -d 2>/dev/null || echo "wordpress")
        DB_USER=$(kubectl get secret mysql-secrets -n $NAMESPACE -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null || echo "wordpress")
        DB_PASSWORD=$(kubectl get secret mysql-secrets -n $NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        
        if [ -z "$DB_PASSWORD" ]; then
            DB_PASSWORD=$(kubectl get secret mysql-secrets -n $NAMESPACE -o jsonpath='{.data.mysql-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        fi
        if [ -z "$DB_PASSWORD" ]; then
            DB_PASSWORD=$(kubectl get secret mysql-secrets -n $NAMESPACE -o jsonpath='{.data.mysql-root-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [ -n "$DB_PASSWORD" ]; then
                DB_USER="root"
            fi
        fi
    fi
    
    # Try wordpress-secrets if mysql-secrets didn't work
    if [ -z "$DB_PASSWORD" ] && kubectl get secret wordpress-secrets -n $NAMESPACE >/dev/null 2>&1; then
        DB_PASSWORD=$(kubectl get secret wordpress-secrets -n $NAMESPACE -o jsonpath='{.data.database-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        if [ -z "$DB_PASSWORD" ]; then
            DB_PASSWORD=$(kubectl get secret wordpress-secrets -n $NAMESPACE -o jsonpath='{.data.mysql-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        fi
    fi
    
    # Fallback: try to get from WordPress pod environment
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${YELLOW}Trying WordPress pod environment variables...${NC}"
        DB_NAME=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -- printenv WORDPRESS_DB_NAME 2>/dev/null || echo "wordpress")
        DB_USER=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -- printenv WORDPRESS_DB_USER 2>/dev/null || echo "wordpress")
        DB_PASSWORD=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -- printenv WORDPRESS_DB_PASSWORD 2>/dev/null || echo "")
    fi
    
    echo -e "${GREEN}Database: $DB_NAME${NC}"
    echo -e "${GREEN}User: $DB_USER${NC}"
    echo -e "${GREEN}Password: ${DB_PASSWORD:+[FOUND]}${DB_PASSWORD:-[NOT FOUND]}${NC}"
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}✗ Could not retrieve database password${NC}"
        echo -e "${YELLOW}Available secrets:${NC}"
        kubectl get secrets -n $NAMESPACE
        echo -e "${YELLOW}Secret contents (mysql-secrets):${NC}"
        kubectl get secret mysql-secrets -n $NAMESPACE -o yaml 2>/dev/null | grep -A 10 "data:" || echo "Secret not found"
        return 1
    fi
}

# Function to backup MySQL database
backup_database() {
    echo -e "${YELLOW}Creating MySQL database backup...${NC}"
    
    local backup_file="$BACKUP_DIR/ethosenv_database_$TIMESTAMP.sql"
    
    # Test database connection first
    echo -e "${BLUE}Testing database connection...${NC}"
    if ! kubectl exec -n $NAMESPACE $MYSQL_POD -- mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${RED}✗ Database connection failed${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Database connection successful${NC}"
    
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
        --comments \
        --dump-date \
        "$DB_NAME" > "$backup_file" 2>/dev/null
    
    if [ -s "$backup_file" ]; then
        echo -e "${GREEN}✓ Database backup created: $backup_file${NC}"
        echo -e "${BLUE}Size: $(du -h "$backup_file" | cut -f1)${NC}"
        
        # Add backup metadata to the SQL file
        {
            echo "-- EthosEnv Database Backup"
            echo "-- Backup Date: $(date)"
            echo "-- Database: $DB_NAME"
            echo "-- Namespace: $NAMESPACE"
            echo "-- MySQL Pod: $MYSQL_POD"
            echo "-- "
            cat "$backup_file"
        } > "$backup_file.tmp" && mv "$backup_file.tmp" "$backup_file"
        
    else
        echo -e "${RED}✗ Database backup failed or is empty${NC}"
        return 1
    fi
}

# Function to backup WordPress files
backup_wordpress_files() {
    echo -e "${YELLOW}Creating WordPress files backup...${NC}"
    
    local backup_file="$BACKUP_DIR/ethosenv_wordpress_$TIMESTAMP.tar.gz"
    
    # Check WordPress directory
    echo -e "${BLUE}Checking WordPress directory...${NC}"
    if ! kubectl exec -n $NAMESPACE $WORDPRESS_POD -- test -d /var/www/html; then
        echo -e "${RED}✗ WordPress directory /var/www/html not found${NC}"
        return 1
    fi
    
    # Show directory contents
    echo -e "${BLUE}WordPress directory contents:${NC}"
    kubectl exec -n $NAMESPACE $WORDPRESS_POD -- ls -la /var/www/html | head -10
    
    # Create tar.gz archive of WordPress files
    echo -e "${BLUE}Creating archive...${NC}"
    kubectl exec -n $NAMESPACE $WORDPRESS_POD -- tar -czf - -C /var/www/html . > "$backup_file"
    
    if [ -s "$backup_file" ]; then
        echo -e "${GREEN}✓ WordPress files backup created: $backup_file${NC}"
        echo -e "${BLUE}Size: $(du -h "$backup_file" | cut -f1)${NC}"
        
        # Test archive integrity
        if tar -tzf "$backup_file" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Archive integrity verified${NC}"
            
            # Show some key files in the archive
            echo -e "${BLUE}Key files in archive:${NC}"
            tar -tzf "$backup_file" | grep -E "(wp-config\.php|wp-content/|\.htaccess)" | head -10 || echo "Standard WordPress files"
        else
            echo -e "${RED}✗ Archive integrity check failed${NC}"
        fi
    else
        echo -e "${RED}✗ WordPress files backup failed or is empty${NC}"
        return 1
    fi
}

# Function to create comprehensive backup info
create_backup_info() {
    local info_file="$BACKUP_DIR/ethosenv_backup_info_$TIMESTAMP.json"
    
    cat > "$info_file" << EOF
{
  "backup_info": {
    "timestamp": "$TIMESTAMP",
    "date": "$(date -Iseconds)",
    "namespace": "$NAMESPACE",
    "mysql_pod": "$MYSQL_POD",
    "wordpress_pod": "$WORDPRESS_POD",
    "database": {
      "name": "$DB_NAME",
      "user": "$DB_USER",
      "backup_file": "ethosenv_database_$TIMESTAMP.sql"
    },
    "wordpress": {
      "path": "/var/www/html",
      "backup_file": "ethosenv_wordpress_$TIMESTAMP.tar.gz"
    },
    "kubernetes_info": {
      "pods": $(kubectl get pods -n $NAMESPACE -o json | jq '.items[] | {name: .metadata.name, status: .status.phase, image: .spec.containers[0].image}'),
      "services": $(kubectl get svc -n $NAMESPACE -o json | jq '.items[] | {name: .metadata.name, type: .spec.type, ports: .spec.ports}'),
      "pvcs": $(kubectl get pvc -n $NAMESPACE -o json | jq '.items[] | {name: .metadata.name, status: .status.phase, capacity: .status.capacity.storage}')
    }
  }
}
EOF

    echo -e "${GREEN}✓ Backup info created: $info_file${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting EthosEnv backup process...${NC}"
    echo -e "${BLUE}Backup directory: $BACKUP_DIR${NC}"
    echo -e "${BLUE}Timestamp: $TIMESTAMP${NC}"
    echo ""
    
    # Get pod names
    get_pod_names
    echo ""
    
    # Get database credentials
    get_db_credentials_from_secrets
    echo ""
    
    # Perform backups
    if backup_database; then
        echo -e "${GREEN}✓ Database backup completed${NC}"
    else
        echo -e "${RED}✗ Database backup failed${NC}"
    fi
    echo ""
    
    if backup_wordpress_files; then
        echo -e "${GREEN}✓ WordPress files backup completed${NC}"
    else
        echo -e "${RED}✗ WordPress files backup failed${NC}"
    fi
    echo ""
    
    # Create backup info
    create_backup_info
    echo ""
    
    # Summary
    echo -e "${GREEN}EthosEnv backup process completed!${NC}"
    echo -e "${BLUE}Backup location: $BACKUP_DIR${NC}"
    echo ""
    echo -e "${YELLOW}Created files:${NC}"
    ls -lh "$BACKUP_DIR"/*"$TIMESTAMP"* 2>/dev/null || echo "No backup files found"
    echo ""
    echo -e "${YELLOW}Total backup size:${NC}"
    du -sh "$BACKUP_DIR" 2>/dev/null || echo "Backup directory not found"
    echo ""
    echo -e "${BLUE}Backup files ready for download or storage!${NC}"
}

# Run main function
main "$@"


