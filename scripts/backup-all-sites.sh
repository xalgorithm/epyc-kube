#!/bin/bash

# All Sites Backup Script
# Creates backups for both EthosEnv and WordPress (Kampfzwerg) sites

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}All WordPress Sites Backup Script${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""

# Function to run backup with error handling
run_backup() {
    local site_name=$1
    local script_path=$2
    
    echo -e "${YELLOW}Starting backup for $site_name...${NC}"
    
    if [ -f "$script_path" ]; then
        if "$script_path"; then
            echo -e "${GREEN}✓ $site_name backup completed successfully${NC}"
            return 0
        else
            echo -e "${RED}✗ $site_name backup failed${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Backup script not found: $script_path${NC}"
        return 1
    fi
}

# Main execution
main() {
    local start_time=$(date +%s)
    local ethosenv_success=0
    local wordpress_success=0
    
    echo -e "${BLUE}Starting backup process for all WordPress sites...${NC}"
    echo -e "${BLUE}Timestamp: $(date)${NC}"
    echo ""
    
    # Backup EthosEnv
    echo -e "${BLUE}=== ETHOSENV BACKUP ===${NC}"
    if run_backup "EthosEnv" "./scripts/backup-ethosenv-dynamic.sh"; then
        ethosenv_success=1
    fi
    echo ""
    
    # Backup WordPress (Kampfzwerg)
    echo -e "${BLUE}=== WORDPRESS (KAMPFZWERG) BACKUP ===${NC}"
    if run_backup "WordPress (Kampfzwerg)" "./scripts/backup-wordpress.sh"; then
        wordpress_success=1
    fi
    echo ""
    
    # Summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "${BLUE}=== BACKUP SUMMARY ===${NC}"
    echo -e "${YELLOW}Duration: ${duration}s${NC}"
    echo ""
    
    if [ $ethosenv_success -eq 1 ]; then
        echo -e "${GREEN}✓ EthosEnv backup: SUCCESS${NC}"
        if [ -d "./backups/ethosenv" ]; then
            echo -e "${BLUE}  Size: $(du -sh ./backups/ethosenv | cut -f1)${NC}"
            echo -e "${BLUE}  Files: $(ls -1 ./backups/ethosenv/*$(date +%Y%m%d)* 2>/dev/null | wc -l || echo 0) created${NC}"
        fi
    else
        echo -e "${RED}✗ EthosEnv backup: FAILED${NC}"
    fi
    
    if [ $wordpress_success -eq 1 ]; then
        echo -e "${GREEN}✓ WordPress backup: SUCCESS${NC}"
        if [ -d "./backups/wordpress" ]; then
            echo -e "${BLUE}  Size: $(du -sh ./backups/wordpress | cut -f1)${NC}"
            echo -e "${BLUE}  Files: $(ls -1 ./backups/wordpress/*$(date +%Y%m%d)* 2>/dev/null | wc -l || echo 0) created${NC}"
        fi
    else
        echo -e "${RED}✗ WordPress backup: FAILED${NC}"
    fi
    
    echo ""
    
    # Overall status
    if [ $ethosenv_success -eq 1 ] && [ $wordpress_success -eq 1 ]; then
        echo -e "${GREEN}🎉 All backups completed successfully!${NC}"
        echo ""
        echo -e "${BLUE}Total backup size:${NC}"
        du -sh ./backups/*/
        echo ""
        echo -e "${YELLOW}Backup locations:${NC}"
        echo -e "${BLUE}• EthosEnv: ./backups/ethosenv/${NC}"
        echo -e "${BLUE}• WordPress: ./backups/wordpress/${NC}"
        return 0
    elif [ $ethosenv_success -eq 1 ] || [ $wordpress_success -eq 1 ]; then
        echo -e "${YELLOW}⚠ Partial backup success - some sites failed${NC}"
        return 1
    else
        echo -e "${RED}✗ All backups failed${NC}"
        return 2
    fi
}

# Run main function
main "$@"

