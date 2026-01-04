#!/bin/bash
# verify-root-cleanliness.sh
# Property 1: Root Directory Cleanliness
# Validates: Requirements 1.1, 1.2, 1.3
#
# For any file in the root directory after reorganization, that file must be
# in the allowed list: *.tf, *.tfvars, README.md, .gitignore, .terraform.lock.hcl,
# kubeconfig.yaml, ssh_config, terraform.tfstate, terraform.tfstate.backup,
# or be a directory.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define allowed file patterns in root directory
ALLOWED_PATTERNS=(
    "*.tf"
    "*.tfvars"
    "README.md"
    ".gitignore"
    ".terraform.lock.hcl"
    "kubeconfig.yaml"
    "ssh_config"
    "terraform.tfstate"
    "terraform.tfstate.backup"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "Root Directory Cleanliness Verification"
echo "=============================================="
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# Function to check if a file matches any allowed pattern
is_allowed_file() {
    local filename="$1"
    
    for pattern in "${ALLOWED_PATTERNS[@]}"; do
        case "$filename" in
            $pattern)
                return 0
                ;;
        esac
    done
    return 1
}

# Get all files (not directories) in root
cd "$PROJECT_ROOT"
VIOLATIONS=()
ALLOWED_FILES=()

for item in * .*; do
    # Skip . and ..
    [[ "$item" == "." || "$item" == ".." ]] && continue
    
    # Skip if item doesn't exist (glob didn't match)
    [[ ! -e "$item" ]] && continue
    
    # Skip directories (they are allowed)
    if [[ -d "$item" ]]; then
        continue
    fi
    
    # Check if file is allowed
    if is_allowed_file "$item"; then
        ALLOWED_FILES+=("$item")
    else
        VIOLATIONS+=("$item")
    fi
done

# Report results
echo "Allowed files found in root:"
echo "----------------------------"
for file in "${ALLOWED_FILES[@]}"; do
    echo -e "  ${GREEN}✓${NC} $file"
done
echo ""

if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS: Root directory is clean${NC}"
    echo "  All files in root match allowed patterns."
    echo ""
    echo "Allowed patterns:"
    for pattern in "${ALLOWED_PATTERNS[@]}"; do
        echo "  - $pattern"
    done
    exit 0
else
    echo -e "${RED}✗ FAIL: Found ${#VIOLATIONS[@]} file(s) that should not be in root${NC}"
    echo ""
    echo "Violations:"
    echo "-----------"
    for file in "${VIOLATIONS[@]}"; do
        echo -e "  ${RED}✗${NC} $file"
    done
    echo ""
    echo "These files should be moved to appropriate directories or removed."
    echo ""
    echo "Suggested actions:"
    for file in "${VIOLATIONS[@]}"; do
        case "$file" in
            *.tar.gz)
                echo "  - $file → Move to backups/"
                ;;
            *.zip)
                echo "  - $file → Move to backups/ or remove if obsolete"
                ;;
            *.txt)
                echo "  - $file → Move to docs/ or remove if temporary"
                ;;
            *.yaml|*.yml)
                echo "  - $file → Move to charts/ or kubernetes/"
                ;;
            .cursorrules|*.code-workspace)
                echo "  - $file → Move to .vscode/"
                ;;
            .DS_Store)
                echo "  - $file → Remove (macOS metadata)"
                ;;
            *)
                echo "  - $file → Review and move to appropriate directory"
                ;;
        esac
    done
    exit 1
fi
