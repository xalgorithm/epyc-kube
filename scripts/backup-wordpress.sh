#!/bin/bash

# WordPress (Kampfzwerg) Backup Script
# Creates SQL dump of MySQL database and tar.gz archive of WordPress files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="kampfzwerg"
BACKUP_DIR="./backups/wordpress"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo -e "${BLUE}WordPress (Kampfzwerg) Backup Script${NC}"
echo -e "${BLUE}====================================${NC}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to get pod names dynamically
get_pod_names() {
    echo -e "${YELLOW}Detecting pods in namespace $NAMESPACE...${NC}"
    
    MYSQL_POD=$(kubectl get pods -n $NAMESPACE -l app=wordpress-mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
                kubectl get pods -n $NAMESPACE | grep -E "mysql|wordpress-mysql" | awk '{print $1}' | head -1 || echo "")
    
    WORDPRESS_POD=$(kubectl get pods -n $NAMESPACE -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
                    kubectl get pods -n $NAMESPACE | grep "^wordpress-" | grep -v mysql | grep -v exporter | awk '{print $1}' | head -1 || echo "")
    
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
    
    # Try wordpress-db-credentials first
    if kubectl get secret wordpress-db-credentials -n $NAMESPACE >/dev/null 2>&1; then
        DB_NAME=$(kubectl get secret wordpress-db-credentials -n $NAMESPACE -o jsonpath='{.data.database}' 2>/dev/null | base64 -d 2>/dev/null || echo "wordpress")
        DB_USER=$(kubectl get secret wordpress-db-credentials -n $NAMESPACE -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null || echo "wordpress")
        DB_PASSWORD=$(kubectl get secret wordpress-db-credentials -n $NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        
        if [ -z "$DB_PASSWORD" ]; then
            DB_PASSWORD=$(kubectl get secret wordpress-db-credentials -n $NAMESPACE -o jsonpath='{.data.mysql-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        fi
        if [ -z "$DB_PASSWORD" ]; then
            DB_PASSWORD=$(kubectl get secret wordpress-db-credentials -n $NAMESPACE -o jsonpath='{.data.mysql-root-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [ -n "$DB_PASSWORD" ]; then
                DB_USER="root"
            fi
        fi
    fi
    
    # Try wordpress-admin-credentials if db-credentials didn't work
    if [ -z "$DB_PASSWORD" ] && kubectl get secret wordpress-admin-credentials -n $NAMESPACE >/dev/null 2>&1; then
        DB_PASSWORD=$(kubectl get secret wordpress-admin-credentials -n $NAMESPACE -o jsonpath='{.data.database-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        if [ -z "$DB_PASSWORD" ]; then
            DB_PASSWORD=$(kubectl get secret wordpress-admin-credentials -n $NAMESPACE -o jsonpath='{.data.mysql-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
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
        echo -e "${YELLOW}Secret contents (wordpress-db-credentials):${NC}"
        kubectl get secret wordpress-db-credentials -n $NAMESPACE -o yaml 2>/dev/null | grep -A 10 "data:" || echo "Secret not found"
        return 1
    fi
}

# Function to backup MySQL database
backup_database() {
    echo -e "${YELLOW}Creating MySQL database backup...${NC}"
    
    local backup_file="$BACKUP_DIR/wordpress_database_$TIMESTAMP.sql"
    
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
            echo "-- WordPress (Kampfzwerg) Database Backup"
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

# SSH config file location (relative to script directory)
SSH_CONFIG="./ssh_config"

# Function to copy file from pod using SSH (primary for large files)
copy_from_pod_with_fallback() {
    local pod_path="$1"
    local local_path="$2"
    local container="$3"
    
    # Get the node where the pod is running
    local node_name=$(kubectl get pod "$WORDPRESS_POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    
    # Try SSH/SCP first (more reliable for large files over NFS)
    if [ -n "$node_name" ] && [ -f "$SSH_CONFIG" ]; then
        echo -e "${BLUE}Using SSH/SCP method (more reliable for large files)...${NC}"
        echo -e "${BLUE}Pod is running on node: $node_name${NC}"
        
        # Find the NFS mount path on the node
        local nfs_mount=$(ssh -F "$SSH_CONFIG" "$node_name" "mount | grep '$NAMESPACE.*wordpress' | head -1 | awk '{print \$3}'" 2>/dev/null)
        if [ -z "$nfs_mount" ]; then
            nfs_mount=$(ssh -F "$SSH_CONFIG" "$node_name" "mount | grep 'kampfzwerg.*wordpress' | head -1 | awk '{print \$3}'" 2>/dev/null)
        fi
        
        if [ -n "$nfs_mount" ]; then
            echo -e "${BLUE}Found NFS mount at: $nfs_mount${NC}"
            
            # Create archive on the node and copy via SCP
            local remote_temp="/tmp/wp_backup_$TIMESTAMP.tar.gz"
            echo -e "${BLUE}Creating archive on node...${NC}"
            if ssh -F "$SSH_CONFIG" "$node_name" "sudo tar -czf $remote_temp -C '$nfs_mount' . 2>/dev/null"; then
                echo -e "${BLUE}Copying archive via SCP...${NC}"
                if scp -F "$SSH_CONFIG" "$node_name:$remote_temp" "$local_path" 2>/dev/null; then
                    # Cleanup remote temp file
                    ssh -F "$SSH_CONFIG" "$node_name" "sudo rm -f $remote_temp" 2>/dev/null || true
                    
                    # Verify the archive
                    if [ -s "$local_path" ] && tar -tzf "$local_path" >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ SSH/SCP method succeeded${NC}"
                        return 0
                    fi
                fi
                ssh -F "$SSH_CONFIG" "$node_name" "sudo rm -f $remote_temp" 2>/dev/null || true
            fi
        fi
        echo -e "${YELLOW}SSH/SCP method failed, falling back to kubectl cp...${NC}"
    fi
    
    # Fallback to kubectl cp
    echo -e "${BLUE}Attempting kubectl cp...${NC}"
    kubectl cp "$NAMESPACE/$WORDPRESS_POD:$pod_path" "$local_path" -c "$container" 2>&1 || true
    
    # Check if file was copied and is valid
    if [ -s "$local_path" ] && tar -tzf "$local_path" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ kubectl cp succeeded${NC}"
        return 0
    fi
    
    echo -e "${RED}✗ All copy methods failed${NC}"
    return 1
}

# Function to backup WordPress files
backup_wordpress_files() {
    echo -e "${YELLOW}Creating WordPress files backup...${NC}"
    
    local backup_file="$BACKUP_DIR/wordpress_files_$TIMESTAMP.tar.gz"
    local temp_archive="/tmp/wordpress_backup_$TIMESTAMP.tar.gz"
    
    # Determine the container name (kampfzwerg uses php-fpm)
    local container_name="php-fpm"
    
    # Check WordPress directory
    echo -e "${BLUE}Checking WordPress directory...${NC}"
    if ! kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- test -d /var/www/html; then
        echo -e "${RED}✗ WordPress directory /var/www/html not found${NC}"
        return 1
    fi
    
    # Show directory size
    echo -e "${BLUE}WordPress directory size:${NC}"
    kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- du -sh /var/www/html 2>/dev/null || echo "Unable to determine size"
    
    # Show directory contents
    echo -e "${BLUE}WordPress directory contents:${NC}"
    kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- ls -la /var/www/html | head -10
    
    # Create tar.gz archive INSIDE the pod first (faster than streaming)
    echo -e "${BLUE}Creating archive inside pod (this may take a few minutes for large sites)...${NC}"
    if ! kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- tar -czf "$temp_archive" -C /var/www/html . 2>&1; then
        echo -e "${RED}✗ Failed to create archive inside pod${NC}"
        return 1
    fi
    
    # Check archive was created
    echo -e "${BLUE}Verifying archive in pod...${NC}"
    local pod_archive_size=$(kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- du -h "$temp_archive" 2>/dev/null | cut -f1)
    if [ -z "$pod_archive_size" ]; then
        echo -e "${RED}✗ Archive not found in pod${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Archive created in pod: $pod_archive_size${NC}"
    
    # Copy archive from pod to local with SSH fallback
    echo -e "${BLUE}Copying archive from pod to local...${NC}"
    if ! copy_from_pod_with_fallback "$temp_archive" "$backup_file" "$container_name"; then
        # Cleanup temp file in pod
        kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- rm -f "$temp_archive" 2>/dev/null || true
        return 1
    fi
    
    # Cleanup temp file in pod
    kubectl exec -n $NAMESPACE $WORDPRESS_POD -c $container_name -- rm -f "$temp_archive" 2>/dev/null || true
    
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
    local info_file="$BACKUP_DIR/wordpress_backup_info_$TIMESTAMP.json"
    
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
      "backup_file": "wordpress_database_$TIMESTAMP.sql"
    },
    "wordpress": {
      "path": "/var/www/html",
      "backup_file": "wordpress_files_$TIMESTAMP.tar.gz"
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

# Function to create backup manifest
create_backup_manifest() {
    local manifest_file="$BACKUP_DIR/wordpress_backup_manifest_$TIMESTAMP.txt"
    
    cat > "$manifest_file" << EOF
WordPress (Kampfzwerg) Backup Manifest
======================================
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
- Database: wordpress_database_$TIMESTAMP.sql
- WordPress Files: wordpress_files_$TIMESTAMP.tar.gz

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
    
    local db_backup="$BACKUP_DIR/wordpress_database_$TIMESTAMP.sql"
    local wp_backup="$BACKUP_DIR/wordpress_files_$TIMESTAMP.tar.gz"
    
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
    echo -e "${BLUE}Starting WordPress (Kampfzwerg) backup process...${NC}"
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
    
    # Create backup info and manifest
    create_backup_info
    create_backup_manifest
    echo ""
    
    # Verify backups
    verify_backups
    echo ""
    
    # Summary
    echo -e "${GREEN}WordPress (Kampfzwerg) backup process completed!${NC}"
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

