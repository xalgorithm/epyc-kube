#!/bin/bash

# Repository Separation Script
# This script separates the epyc repository into:
# - epyc-private: Contains unsanitized content (current main branch)
# - epyc-kube: Contains sanitized content (backup-sanitized-20251228 branch)

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          REPOSITORY SEPARATION SCRIPT                         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in the right directory
if [ ! -d ".git" ]; then
    echo "❌ Error: Not in a git repository"
    exit 1
fi

# Check if remotes exist
if ! git remote | grep -q "epyc-private"; then
    echo "Adding remote: epyc-private..."
    git remote add epyc-private git@github.com:xalgorithm/epyc-private.git
fi

if ! git remote | grep -q "epyc-kube"; then
    echo "❌ Error: epyc-kube remote not found"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 1: Push unsanitized content to epyc-private"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Ensure we're on main branch
git checkout main 2>&1

echo "Current commit: $(git log -1 --oneline)"
echo ""
echo "Pushing to epyc-private/main..."
echo "⚠️  This contains ORIGINAL credentials and sensitive data"
echo ""

if git push -u epyc-private main --force 2>&1; then
    echo "✓ Successfully pushed to epyc-private"
else
    echo "❌ Failed to push to epyc-private"
    echo "   Make sure the repository exists at: https://github.com/xalgorithm/epyc-private"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 2: Push sanitized content to epyc-kube"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if backup branch exists
if ! git rev-parse --verify backup-sanitized-20251228 >/dev/null 2>&1; then
    echo "❌ Error: backup-sanitized-20251228 branch not found"
    exit 1
fi

echo "Checking out sanitized branch: backup-sanitized-20251228"
git checkout backup-sanitized-20251228 2>&1

echo ""
echo "Current commit: $(git log -1 --oneline)"
echo ""
echo "Creating/updating main branch from sanitized content..."

# Create a new main branch from the sanitized content
git branch -D main-sanitized 2>/dev/null || true
git checkout -b main-sanitized 2>&1

echo ""
echo "Pushing to epyc-kube/main..."
echo "✓ This contains SANITIZED/REDACTED content"
echo ""

if git push epyc-kube main-sanitized:main --force 2>&1; then
    echo "✓ Successfully pushed sanitized content to epyc-kube"
else
    echo "❌ Failed to push to epyc-kube"
    exit 1
fi

# Update origin to point to epyc-kube as well
echo ""
echo "Updating origin remote..."
git push origin main-sanitized:main --force 2>&1

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 3: Clean up and set tracking branches"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Switch back to main and update it to track epyc-private
git checkout main 2>&1
git branch --set-upstream-to=epyc-private/main main

echo "✓ Main branch now tracks epyc-private/main"
echo ""

# Create a sanitized branch that tracks epyc-kube
git checkout main-sanitized 2>&1
git branch --set-upstream-to=epyc-kube/main main-sanitized

echo "✓ main-sanitized branch now tracks epyc-kube/main"
echo ""

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          REPOSITORY SEPARATION COMPLETE! ✅                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "SUMMARY:"
echo ""
echo "📦 epyc-private (PRIVATE)"
echo "   URL: https://github.com/xalgorithm/epyc-private"
echo "   Branch: main"
echo "   Content: Original credentials and configuration"
echo "   Local tracking: 'main' branch"
echo ""
echo "📦 epyc-kube (PUBLIC-SAFE)"
echo "   URL: https://github.com/xalgorithm/epyc-kube"
echo "   Branch: main"
echo "   Content: Sanitized/redacted configuration"
echo "   Local tracking: 'main-sanitized' branch"
echo ""
echo "USAGE:"
echo ""
echo "  Work with private content:"
echo "    git checkout main"
echo "    git push epyc-private main"
echo ""
echo "  Work with public/sanitized content:"
echo "    git checkout main-sanitized"
echo "    git push epyc-kube main-sanitized:main"
echo ""
echo "REMOTES CONFIGURED:"
git remote -v | grep -E "(epyc-private|epyc-kube)"
echo ""
echo "═══════════════════════════════════════════════════════════════"

