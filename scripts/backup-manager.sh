#!/bin/bash

# EthosEnv Backup Manager
# Manages backups, restoration, and cleanup for EthosEnv

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BACKUP_DIR="./backups/ethosenv"
NAMESPACE="ethosenv"

show_usage() {
    echo -e "${BLUE}EthosEnv Backup Manager${NC}"
    echo -e "${BLUE}=======================${NC}"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  backup     Create new backup (SQL + WordPress files)"
    echo "  list       List all available backups"
    echo "  verify     Verify latest backup integrity"
    echo "  cleanup    Remove old backups (keep last 5)"
    echo "  info       Show backup information"
    echo "  restore    Show restoration instructions"
    echo ""
    echo "Examples:"
    echo "  $0 backup          # Create new backup"
    echo "  $0 list            # List all backups"
    echo "  $0 verify          # Verify latest backup"
    echo "  $0 cleanup         # Clean old backups"
}

create_backup() {
    echo -e "${BLUE}Creating new EthosEnv backup...${NC}"
    ./scripts/backup-ethosenv-dynamic.sh
}

list_backups() {
    echo -e "${BLUE}Available EthosEnv Backups${NC}"
    echo -e "${BLUE}==========================${NC}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}No backup directory found${NC}"
        return
    fi
    
    echo -e "${YELLOW}SQL Backups:${NC}"
    ls -lah "$BACKUP_DIR"/ethosenv_database_*.sql 2>/dev/null | while read -r line; do
        echo "  $line"
    done || echo "  No SQL backups found"
    
    echo ""
    echo -e "${YELLOW}WordPress File Backups:${NC}"
    ls -lah "$BACKUP_DIR"/ethosenv_wordpress_*.tar.gz 2>/dev/null | while read -r line; do
        echo "  $line"
    done || echo "  No WordPress backups found"
    
    echo ""
    echo -e "${YELLOW}Backup Info Files:${NC}"
    ls -lah "$BACKUP_DIR"/ethosenv_backup_info_*.json 2>/dev/null | while read -r line; do
        echo "  $line"
    done || echo "  No info files found"
    
    echo ""
    echo -e "${BLUE}Total backup directory size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0B")${NC}"
}

verify_backup() {
    echo -e "${BLUE}Verifying latest backup...${NC}"
    ./scripts/verify-backup.sh
}

cleanup_backups() {
    echo -e "${BLUE}Cleaning up old backups (keeping last 5)...${NC}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}No backup directory found${NC}"
        return
    fi
    
    # Clean SQL backups
    SQL_COUNT=$(ls -1 "$BACKUP_DIR"/ethosenv_database_*.sql 2>/dev/null | wc -l || echo 0)
    if [ "$SQL_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}Removing old SQL backups...${NC}"
        ls -t "$BACKUP_DIR"/ethosenv_database_*.sql | tail -n +6 | xargs rm -f
        echo -e "${GREEN}✓ Removed $((SQL_COUNT - 5)) old SQL backups${NC}"
    else
        echo -e "${GREEN}✓ SQL backups: $SQL_COUNT (no cleanup needed)${NC}"
    fi
    
    # Clean WordPress backups
    WP_COUNT=$(ls -1 "$BACKUP_DIR"/ethosenv_wordpress_*.tar.gz 2>/dev/null | wc -l || echo 0)
    if [ "$WP_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}Removing old WordPress backups...${NC}"
        ls -t "$BACKUP_DIR"/ethosenv_wordpress_*.tar.gz | tail -n +6 | xargs rm -f
        echo -e "${GREEN}✓ Removed $((WP_COUNT - 5)) old WordPress backups${NC}"
    else
        echo -e "${GREEN}✓ WordPress backups: $WP_COUNT (no cleanup needed)${NC}"
    fi
    
    # Clean info files
    INFO_COUNT=$(ls -1 "$BACKUP_DIR"/ethosenv_backup_info_*.json 2>/dev/null | wc -l || echo 0)
    if [ "$INFO_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}Removing old info files...${NC}"
        ls -t "$BACKUP_DIR"/ethosenv_backup_info_*.json | tail -n +6 | xargs rm -f
        echo -e "${GREEN}✓ Removed $((INFO_COUNT - 5)) old info files${NC}"
    else
        echo -e "${GREEN}✓ Info files: $INFO_COUNT (no cleanup needed)${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Cleanup completed. Current backup size: $(du -sh "$BACKUP_DIR" | cut -f1)${NC}"
}

show_info() {
    echo -e "${BLUE}EthosEnv Backup Information${NC}"
    echo -e "${BLUE}===========================${NC}"
    
    # Show Kubernetes resources
    echo -e "${YELLOW}Kubernetes Resources:${NC}"
    echo "Namespace: $NAMESPACE"
    echo "Pods:"
    kubectl get pods -n $NAMESPACE | grep -E "(mysql|wordpress)" || echo "  No pods found"
    echo ""
    echo "Services:"
    kubectl get svc -n $NAMESPACE | grep -E "(mysql|wordpress)" || echo "  No services found"
    echo ""
    echo "PVCs:"
    kubectl get pvc -n $NAMESPACE || echo "  No PVCs found"
    echo ""
    
    # Show backup status
    if [ -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}Backup Status:${NC}"
        LATEST_SQL=$(ls -t "$BACKUP_DIR"/ethosenv_database_*.sql 2>/dev/null | head -1 || echo "")
        LATEST_WP=$(ls -t "$BACKUP_DIR"/ethosenv_wordpress_*.tar.gz 2>/dev/null | head -1 || echo "")
        
        if [ -n "$LATEST_SQL" ]; then
            echo "Latest SQL backup: $(basename "$LATEST_SQL")"
            echo "  Size: $(du -h "$LATEST_SQL" | cut -f1)"
            echo "  Date: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LATEST_SQL")"
        else
            echo "Latest SQL backup: None"
        fi
        
        if [ -n "$LATEST_WP" ]; then
            echo "Latest WordPress backup: $(basename "$LATEST_WP")"
            echo "  Size: $(du -h "$LATEST_WP" | cut -f1)"
            echo "  Date: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LATEST_WP")"
        else
            echo "Latest WordPress backup: None"
        fi
    else
        echo -e "${YELLOW}No backups found${NC}"
    fi
}

show_restore_instructions() {
    echo -e "${BLUE}EthosEnv Restoration Instructions${NC}"
    echo -e "${BLUE}==================================${NC}"
    echo ""
    echo -e "${YELLOW}Database Restoration:${NC}"
    echo "1. Copy SQL file to MySQL pod:"
    echo "   kubectl cp backup.sql $NAMESPACE/mysql-pod:/tmp/backup.sql"
    echo ""
    echo "2. Restore database:"
    echo "   kubectl exec -n $NAMESPACE mysql-pod -- mysql -u wordpress -p wordpress < /tmp/backup.sql"
    echo ""
    echo -e "${YELLOW}WordPress Files Restoration:${NC}"
    echo "1. Extract files locally:"
    echo "   tar -xzf ethosenv_wordpress_TIMESTAMP.tar.gz"
    echo ""
    echo "2. Copy to WordPress pod:"
    echo "   kubectl cp extracted-files/. $NAMESPACE/wordpress-pod:/var/www/html/"
    echo ""
    echo "3. Fix permissions:"
    echo "   kubectl exec -n $NAMESPACE wordpress-pod -- chown -R www-data:www-data /var/www/html"
    echo ""
    echo -e "${RED}⚠️  IMPORTANT:${NC}"
    echo "- Always test restoration in a staging environment first"
    echo "- Backup current data before restoring"
    echo "- Verify file permissions after restoration"
    echo "- Update wp-config.php if database credentials changed"
}

# Main execution
case "${1:-help}" in
    backup)
        create_backup
        ;;
    list)
        list_backups
        ;;
    verify)
        verify_backup
        ;;
    cleanup)
        cleanup_backups
        ;;
    info)
        show_info
        ;;
    restore)
        show_restore_instructions
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac


