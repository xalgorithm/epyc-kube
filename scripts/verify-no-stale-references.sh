#!/bin/bash
# verify-no-stale-references.sh
# Property 2: No Stale Path References
# Validates: Requirements 4.3, 8.1, 9.1
#
# For any shell script or markdown file in the repository, there should be
# no references to old paths (kubernetes/nfty/, orphaned root files by their
# old paths, kubernetes/ethosenv/).
#
# Note: This script excludes:
#   - .kiro/specs/ (spec docs that document the changes)
#   - docs/ORGANIZATION-SUMMARY.md (documents the reorganization)
#   - This script itself (needs to reference old paths to check for them)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "Stale Path References Verification"
echo "=============================================="
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

cd "$PROJECT_ROOT"

TOTAL_VIOLATIONS=0
VIOLATION_DETAILS=""

# Function to search for stale paths, excluding legitimate references
# Arguments: $1 = pattern to search for, $2 = description
search_stale_path() {
    local pattern="$1"
    local description="$2"
    
    # Search in shell scripts, markdown, and yaml files
    # Exclude: .git, .kiro/specs, node_modules, .terraform, this script, ORGANIZATION-SUMMARY.md
    local matches
    matches=$(grep -rn --include="*.sh" --include="*.md" --include="*.yaml" --include="*.yml" \
        --exclude-dir=".git" \
        --exclude-dir=".kiro" \
        --exclude-dir="node_modules" \
        --exclude-dir=".terraform" \
        --exclude="$SCRIPT_NAME" \
        --exclude="ORGANIZATION-SUMMARY.md" \
        "$pattern" . 2>/dev/null || true)
    
    echo "$matches"
}

echo "Checking for stale path references..."
echo "(Excluding: .kiro/specs/, docs/ORGANIZATION-SUMMARY.md, this script)"
echo ""

# Check 1: kubernetes/nfty (renamed to kubernetes/ntfy)
echo -n "1. Checking for 'kubernetes/nfty'... "
matches=$(search_stale_path "kubernetes/nfty" "Renamed to kubernetes/ntfy")
if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
    echo -e "${RED}FOUND ($count reference(s))${NC}"
    VIOLATION_DETAILS="${VIOLATION_DETAILS}\n${YELLOW}Stale path: kubernetes/nfty (should be kubernetes/ntfy)${NC}\n$matches\n"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + count))
else
    echo -e "${GREEN}OK${NC}"
fi

# Check 2: kubernetes/ethosenv/ (consolidated into kubernetes/ethosenv-k8s)
echo -n "2. Checking for 'kubernetes/ethosenv/'... "
# Need to be careful not to match kubernetes/ethosenv-k8s
matches=$(search_stale_path "kubernetes/ethosenv/" "Consolidated into kubernetes/ethosenv-k8s")
if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
    echo -e "${RED}FOUND ($count reference(s))${NC}"
    VIOLATION_DETAILS="${VIOLATION_DETAILS}\n${YELLOW}Stale path: kubernetes/ethosenv/ (should be kubernetes/ethosenv-k8s/)${NC}\n$matches\n"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + count))
else
    echo -e "${GREEN}OK${NC}"
fi

# Check 3: Root-level Divi.zip references (moved/deleted)
echo -n "3. Checking for root-level 'Divi.zip'... "
matches=$(search_stale_path "Divi\.zip" "Moved to backups or deleted")
# Filter out references that are in backups/ directory
matches=$(echo "$matches" | grep -v "backups/" || true)
if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
    echo -e "${RED}FOUND ($count reference(s))${NC}"
    VIOLATION_DETAILS="${VIOLATION_DETAILS}\n${YELLOW}Stale root file: Divi.zip (should be in backups/ or removed)${NC}\n$matches\n"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + count))
else
    echo -e "${GREEN}OK${NC}"
fi

# Check 4: Root-level couchdb_metrics.txt references (deleted)
echo -n "4. Checking for 'couchdb_metrics.txt'... "
matches=$(search_stale_path "couchdb_metrics\.txt" "Deleted temporary file")
if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
    echo -e "${RED}FOUND ($count reference(s))${NC}"
    VIOLATION_DETAILS="${VIOLATION_DETAILS}\n${YELLOW}Stale root file: couchdb_metrics.txt (should be deleted)${NC}\n$matches\n"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + count))
else
    echo -e "${GREEN}OK${NC}"
fi

# Check 5: Root-level values.yaml references (moved to charts/)
echo -n "5. Checking for root-level 'values.yaml'... "
# Only flag if it's a root reference, not references to values.yaml in subdirectories
matches=$(grep -rn --include="*.sh" --include="*.md" \
    --exclude-dir=".git" \
    --exclude-dir=".kiro" \
    --exclude-dir="node_modules" \
    --exclude-dir=".terraform" \
    --exclude="$SCRIPT_NAME" \
    --exclude="ORGANIZATION-SUMMARY.md" \
    "\./values\.yaml\|^values\.yaml" . 2>/dev/null || true)
if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
    echo -e "${RED}FOUND ($count reference(s))${NC}"
    VIOLATION_DETAILS="${VIOLATION_DETAILS}\n${YELLOW}Stale root file: values.yaml (should be in charts/ or kubernetes/)${NC}\n$matches\n"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + count))
else
    echo -e "${GREEN}OK${NC}"
fi

# Check 6: Root-level .cursorrules references (moved to .vscode/ or config/)
echo -n "6. Checking for root-level '.cursorrules'... "
matches=$(grep -rn --include="*.sh" --include="*.md" \
    --exclude-dir=".git" \
    --exclude-dir=".kiro" \
    --exclude-dir="node_modules" \
    --exclude-dir=".terraform" \
    --exclude="$SCRIPT_NAME" \
    --exclude="ORGANIZATION-SUMMARY.md" \
    "\./\.cursorrules\|^\.cursorrules" . 2>/dev/null || true)
if [[ -n "$matches" ]]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
    echo -e "${RED}FOUND ($count reference(s))${NC}"
    VIOLATION_DETAILS="${VIOLATION_DETAILS}\n${YELLOW}Stale root file: .cursorrules (should be in .vscode/ or config/)${NC}\n$matches\n"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + count))
else
    echo -e "${GREEN}OK${NC}"
fi

echo ""

# Report detailed violations
if [[ $TOTAL_VIOLATIONS -gt 0 ]]; then
    echo "=============================================="
    echo -e "${RED}DETAILED VIOLATIONS${NC}"
    echo "=============================================="
    echo -e "$VIOLATION_DETAILS"
fi

# Final summary
echo "=============================================="
echo "SUMMARY"
echo "=============================================="
echo ""

if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS: No stale path references found${NC}"
    echo ""
    echo "Checked for these stale paths:"
    echo "  - kubernetes/nfty/ (renamed to kubernetes/ntfy/)"
    echo "  - kubernetes/ethosenv/ (consolidated into kubernetes/ethosenv-k8s/)"
    echo "  - Root-level Divi.zip"
    echo "  - Root-level couchdb_metrics.txt"
    echo "  - Root-level values.yaml"
    echo "  - Root-level .cursorrules"
    echo ""
    echo "Excluded from search (legitimate references):"
    echo "  - .kiro/specs/ (spec documentation)"
    echo "  - docs/ORGANIZATION-SUMMARY.md (reorganization documentation)"
    echo "  - This verification script"
    exit 0
else
    echo -e "${RED}✗ FAIL: Found $TOTAL_VIOLATIONS stale path reference(s)${NC}"
    echo ""
    echo "These references should be updated to use the new paths:"
    echo "  - kubernetes/nfty/ → kubernetes/ntfy/"
    echo "  - kubernetes/ethosenv/ → kubernetes/ethosenv-k8s/"
    echo "  - Root files → Their new locations in backups/, .vscode/, config/, charts/"
    exit 1
fi
