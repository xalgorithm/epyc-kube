#!/bin/bash

# Test different tar methods to find the best one for macOS
# This script helps determine which tar approach works best

SOURCE_DIR="../ethosenv/wordpress"
TEST_ARCHIVE="/tmp/test-wordpress.tar.gz"

echo "🧪 Testing tar methods for WordPress content migration..."

if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Source directory not found: $SOURCE_DIR"
    exit 1
fi

cd "$SOURCE_DIR"

echo ""
echo "📁 Source directory: $SOURCE_DIR"
echo "📊 File count: $(find . -type f | wc -l)"
echo "💾 Directory size: $(du -sh . | cut -f1)"

echo ""
echo "🔍 Testing Method 1: Standard tar..."
if tar -czf "$TEST_ARCHIVE.1" --exclude='.DS_Store' . 2>/tmp/tar1.log; then
    echo "✅ Method 1: Success"
    echo "📦 Archive size: $(ls -lh $TEST_ARCHIVE.1 | awk '{print $5}')"
    if [ -s /tmp/tar1.log ]; then
        echo "⚠️  Warnings found:"
        head -3 /tmp/tar1.log
        echo "   ($(wc -l < /tmp/tar1.log) total warning lines)"
    else
        echo "✅ No warnings"
    fi
else
    echo "❌ Method 1: Failed"
fi

echo ""
echo "🔍 Testing Method 2: tar with error suppression..."
if tar -czf "$TEST_ARCHIVE.2" --exclude='.DS_Store' . 2>/dev/null; then
    echo "✅ Method 2: Success (warnings suppressed)"
    echo "📦 Archive size: $(ls -lh $TEST_ARCHIVE.2 | awk '{print $5}')"
else
    echo "❌ Method 2: Failed"
fi

echo ""
echo "🔍 Testing Method 3: GNU tar (if available)..."
GNUTAR=$(which gtar 2>/dev/null || echo "")
if [ -n "$GNUTAR" ] && $GNUTAR --version 2>/dev/null | grep -q "GNU tar"; then
    if $GNUTAR -czf "$TEST_ARCHIVE.3" --exclude='.DS_Store' --no-xattrs . 2>/tmp/tar3.log; then
        echo "✅ Method 3: Success (GNU tar with --no-xattrs)"
        echo "📦 Archive size: $(ls -lh $TEST_ARCHIVE.3 | awk '{print $5}')"
        if [ -s /tmp/tar3.log ]; then
            echo "⚠️  Warnings: $(wc -l < /tmp/tar3.log) lines"
        else
            echo "✅ No warnings"
        fi
    else
        echo "❌ Method 3: Failed"
    fi
else
    echo "ℹ️  Method 3: GNU tar not available (install with: brew install gnu-tar)"
fi

echo ""
echo "🧹 Cleaning up test files..."
rm -f "$TEST_ARCHIVE".*
rm -f /tmp/tar*.log

echo ""
echo "💡 Recommendations:"
echo "1. If you see extended attribute warnings, they are usually harmless"
echo "2. Use migrate-wordpress-content-alt.sh for a warning-free experience"
echo "3. Install GNU tar with 'brew install gnu-tar' for better macOS support"

echo ""
echo "✅ Test completed!"