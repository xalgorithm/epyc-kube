#!/bin/bash

# Git History Sanitization Script
# Removes emails, passwords, IPs, and domains from git history

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     GIT HISTORY SANITIZATION SCRIPT                           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Backup current state
echo "Creating backup branch..."
BACKUP_BRANCH="backup-before-sanitization-$(date +%Y%m%d-%H%M%S)"
git branch "$BACKUP_BRANCH"
echo "✓ Backup created: $BACKUP_BRANCH"
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "SENSITIVE DATA TO BE REMOVED:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "PASSWORDS:"
echo "  - Pr1amsf0lly!           → <REDACTED_PASSWORD>"
echo "  - Pr1amsf0lly            → <REDACTED_PASSWORD>"
echo "  - UHIxYW1zZjBsbHkh (b64) → <REDACTED_PASSWORD_B64>"
echo "  - UHIxYW1zZjBsbHk= (b64) → <REDACTED_PASSWORD_B64>"
echo ""
echo "EMAILS:"
echo "  - x.algorithm@gmail.com  → admin@example.com"
echo "  - find.me@xalg.im        → contact@example.com"
echo ""
echo "USERNAMES:"
echo "  - xalg                   → admin"
echo ""
echo "GIT AUTHOR/COMMITTER:"
echo "  - x.algorithm@gmail.com  → admin@example.com"
echo ""
echo "IP ADDRESSES:"
echo "  - 107.172.99.x           → 10.0.1.x"
echo "  - 198.55.108.x           → 10.0.2.x"
echo "  - 192.168.0.x            → 192.168.100.x"
echo ""
echo "DOMAINS:"
echo "  - *.xalg.im              → *.gray-beard.com"
echo "  - kampfzwerg.me          → kampfzwerg.gray-beard.com"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Ask for confirmation
read -p "Proceed with sanitization? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Sanitization cancelled"
    exit 1
fi

echo ""
echo "Starting git filter-branch..."
echo ""

# Create temporary script for filtering
cat > /tmp/git-filter-script.sh << 'EOF'
#!/bin/bash

# Read the tree content
git ls-tree -r "$GIT_COMMIT" | 
while read mode type hash path; do
    if [ "$type" = "blob" ]; then
        # Get the file content
        content=$(git cat-file blob "$hash")
        
        # Apply replacements
        content=$(echo "$content" | \
            sed -e 's/Pr1amsf0lly!/<REDACTED_PASSWORD>/g' \
                -e 's/Pr1amsf0lly/<REDACTED_PASSWORD>/g' \
                -e 's/x\.algorithm@gmail\.com/admin@example.com/g' \
                -e 's/find\.me@xalg\.im/contact@example.com/g' \
                -e 's/\bxalg\b/admin/g' \
                -e 's/107\.172\.99\./10.0.1./g' \
                -e 's/198\.55\.108\./10.0.2./g' \
                -e 's/192\.168\.0\./192.168.100./g' \
                -e 's/\.xalg\.im/.gray-beard.com/g' \
                -e 's/xalg\.im/gray-beard.com/g' \
                -e 's/kampfzwerg\.me/kampfzwerg.gray-beard.com/g')
        
        # Write modified content
        new_hash=$(echo "$content" | git hash-object -w --stdin)
        echo "$mode $type $new_hash	$path"
    else
        echo "$mode $type $hash	$path"
    fi
done | git mktree
EOF

chmod +x /tmp/git-filter-script.sh

# Run git filter-branch to sanitize file contents and commit metadata
git filter-branch --force \
    --env-filter '
        # Change author email
        if [ "$GIT_AUTHOR_EMAIL" = "x.algorithm@gmail.com" ]; then
            export GIT_AUTHOR_NAME="Admin User"
            export GIT_AUTHOR_EMAIL="admin@example.com"
        fi
        # Change committer email
        if [ "$GIT_COMMITTER_EMAIL" = "x.algorithm@gmail.com" ]; then
            export GIT_COMMITTER_NAME="Admin User"
            export GIT_COMMITTER_EMAIL="admin@example.com"
        fi
    ' \
    --tree-filter '
        # Process all files in the working directory
        find . -type f \( \
            -name "*.sh" -o \
            -name "*.yaml" -o \
            -name "*.yml" -o \
            -name "*.md" -o \
            -name "*.tf" -o \
            -name "*.sql" -o \
            -name "*.conf" -o \
            -name "*.txt" -o \
            -name "*.tftpl" \
        \) -exec sed -i.bak \
            -e "s/Pr1amsf0lly!/<REDACTED_PASSWORD>/g" \
            -e "s/Pr1amsf0lly/<REDACTED_PASSWORD>/g" \
            -e "s/UHIxYW1zZjBsbHkh/<REDACTED_PASSWORD_B64>/g" \
            -e "s/UHIxYW1zZjBsbHk=/<REDACTED_PASSWORD_B64>/g" \
            -e "s/x\.algorithm@gmail\.com/admin@example.com/g" \
            -e "s/find\.me@xalg\.im/contact@example.com/g" \
            -e "s/\bxalg\b/admin/g" \
            -e "s/107\.172\.99\./10.0.1./g" \
            -e "s/198\.55\.108\./10.0.2./g" \
            -e "s/192\.168\.0\./192.168.100./g" \
            -e "s/\.xalg\.im/.gray-beard.com/g" \
            -e "s/xalg\.im/gray-beard.com/g" \
            -e "s/kampfzwerg\.me/kampfzwerg.gray-beard.com/g" \
            {} \; 2>/dev/null || true
        
        # Remove backup files
        find . -name "*.bak" -delete 2>/dev/null || true
    ' \
    --tag-name-filter cat -- --all

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Cleaning up..."
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Clean up refs
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     SANITIZATION COMPLETE                                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "BACKUP AVAILABLE:"
echo "  Branch: $BACKUP_BRANCH"
echo "  To restore: git checkout $BACKUP_BRANCH"
echo ""
echo "VERIFICATION:"
echo "  Check files for sensitive data before pushing!"
echo ""
echo "TO PUSH SANITIZED HISTORY:"
echo "  git push --force --all"
echo "  git push --force --tags"
echo ""
echo "⚠️  WARNING: This will overwrite remote history!"
echo ""

