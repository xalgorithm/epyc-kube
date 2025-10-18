#!/bin/bash

# WordPress Backup Verification Script
# Verifies the integrity and contents of WordPress (Kampfzwerg) backups

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BACKUP_DIR="./backups/wordpress"

echo -e "${BLUE}WordPress (Kampfzwerg) Backup Verification${NC}"
echo -e "${BLUE}==========================================${NC}"

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}✗ Backup directory not found: $BACKUP_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Backup directory contents:${NC}"
ls -lah "$BACKUP_DIR"
echo ""

# Find the most recent backup files
LATEST_SQL=$(ls -t "$BACKUP_DIR"/wordpress_database_*.sql 2>/dev/null | head -1 || echo "")
LATEST_TAR=$(ls -t "$BACKUP_DIR"/wordpress_files_*.tar.gz 2>/dev/null | head -1 || echo "")
LATEST_INFO=$(ls -t "$BACKUP_DIR"/wordpress_backup_info_*.json 2>/dev/null | head -1 || echo "")

# Verify SQL backup
if [ -n "$LATEST_SQL" ] && [ -f "$LATEST_SQL" ]; then
    echo -e "${YELLOW}Verifying SQL backup: $(basename "$LATEST_SQL")${NC}"
    
    # Check file size
    SQL_SIZE=$(du -h "$LATEST_SQL" | cut -f1)
    SQL_LINES=$(wc -l < "$LATEST_SQL")
    echo -e "${GREEN}✓ Size: $SQL_SIZE${NC}"
    echo -e "${GREEN}✓ Lines: $SQL_LINES${NC}"
    
    # Check for WordPress tables
    if grep -q "CREATE TABLE.*wp_" "$LATEST_SQL"; then
        WP_TABLES=$(grep -c "CREATE TABLE.*wp_" "$LATEST_SQL")
        echo -e "${GREEN}✓ WordPress tables found: $WP_TABLES${NC}"
    else
        echo -e "${YELLOW}⚠ No standard WordPress tables found (might use different prefix)${NC}"
    fi
    
    # Check for data
    if grep -q "INSERT INTO" "$LATEST_SQL"; then
        INSERT_COUNT=$(grep -c "INSERT INTO" "$LATEST_SQL")
        echo -e "${GREEN}✓ Data inserts found: $INSERT_COUNT${NC}"
    else
        echo -e "${YELLOW}⚠ No data inserts found${NC}"
    fi
    
    # Show database info from backup
    echo -e "${BLUE}Database backup info:${NC}"
    head -10 "$LATEST_SQL" | grep -E "^--" || echo "No header comments found"
    
else
    echo -e "${RED}✗ No SQL backup found${NC}"
fi

echo ""

# Verify WordPress files backup
if [ -n "$LATEST_TAR" ] && [ -f "$LATEST_TAR" ]; then
    echo -e "${YELLOW}Verifying WordPress backup: $(basename "$LATEST_TAR")${NC}"
    
    # Check file size
    TAR_SIZE=$(du -h "$LATEST_TAR" | cut -f1)
    echo -e "${GREEN}✓ Size: $TAR_SIZE${NC}"
    
    # Test archive integrity
    if tar -tzf "$LATEST_TAR" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Archive integrity verified${NC}"
        
        # Count files
        FILE_COUNT=$(tar -tzf "$LATEST_TAR" | wc -l)
        echo -e "${GREEN}✓ Files in archive: $FILE_COUNT${NC}"
        
        # Check for key WordPress files
        echo -e "${BLUE}Key WordPress files:${NC}"
        tar -tzf "$LATEST_TAR" | grep -E "(wp-config\.php|wp-content/themes|wp-content/plugins|wp-content/uploads)" | head -5 || echo "Standard files present"
        
        # Check for wp-config.php
        if tar -tzf "$LATEST_TAR" | grep -q "wp-config\.php"; then
            echo -e "${GREEN}✓ wp-config.php found${NC}"
        else
            echo -e "${YELLOW}⚠ wp-config.php not found${NC}"
        fi
        
        # Check for themes and plugins
        THEMES=$(tar -tzf "$LATEST_TAR" | grep "wp-content/themes/" | wc -l)
        PLUGINS=$(tar -tzf "$LATEST_TAR" | grep "wp-content/plugins/" | wc -l)
        UPLOADS=$(tar -tzf "$LATEST_TAR" | grep "wp-content/uploads/" | wc -l)
        
        echo -e "${GREEN}✓ Themes: $THEMES files${NC}"
        echo -e "${GREEN}✓ Plugins: $PLUGINS files${NC}"
        echo -e "${GREEN}✓ Uploads: $UPLOADS files${NC}"
        
    else
        echo -e "${RED}✗ Archive integrity check failed${NC}"
    fi
else
    echo -e "${RED}✗ No WordPress backup found${NC}"
fi

echo ""

# Show backup info
if [ -n "$LATEST_INFO" ] && [ -f "$LATEST_INFO" ]; then
    echo -e "${YELLOW}Backup information:${NC}"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.backup_info | "Date: \(.date)\nNamespace: \(.namespace)\nDatabase: \(.database.name)\nMySQL Pod: \(.mysql_pod)\nWordPress Pod: \(.wordpress_pod)"' "$LATEST_INFO"
    else
        echo "Backup info file found: $(basename "$LATEST_INFO")"
        echo "Install 'jq' to view formatted backup information"
    fi
else
    echo -e "${YELLOW}⚠ No backup info file found${NC}"
fi

echo ""
echo -e "${GREEN}Backup verification completed!${NC}"

# Summary
echo ""
echo -e "${BLUE}=== BACKUP SUMMARY ===${NC}"
echo -e "${YELLOW}SQL Backup:${NC} ${LATEST_SQL:+✓ $(basename "$LATEST_SQL")}${LATEST_SQL:-✗ Not found}"
echo -e "${YELLOW}WordPress Files:${NC} ${LATEST_TAR:+✓ $(basename "$LATEST_TAR")}${LATEST_TAR:-✗ Not found}"
echo -e "${YELLOW}Backup Info:${NC} ${LATEST_INFO:+✓ $(basename "$LATEST_INFO")}${LATEST_INFO:-✗ Not found}"
echo ""
echo -e "${BLUE}Total backup size: $(du -sh "$BACKUP_DIR" | cut -f1)${NC}"
