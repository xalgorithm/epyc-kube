#!/bin/bash

# Script launcher for ethosenv-k8s scripts
# Usage: ./run-script.sh <script-name>

set -euo pipefail

SCRIPT_NAME="$1"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ -z "${SCRIPT_NAME:-}" ]; then
    echo "🚀 WordPress Kubernetes Scripts"
    echo ""
    echo "Usage: ./run-script.sh <script-name>"
    echo ""
    echo "Available scripts:"
    echo ""
    echo "📦 Deployment Scripts:"
    echo "  master-deploy-wordpress    - Complete deployment with all fixes"
    echo "  deploy-wordpress          - Basic WordPress deployment"
    echo "  quick-start              - Quick deployment guide"
    echo ""
    echo "🔧 Setup & Configuration:"
    echo "  install-cert-manager     - Install cert-manager for SSL"
    echo "  configure-dns           - DNS configuration guide"
    echo "  configure-php-uploads   - Configure PHP settings (32M uploads, FPM tuning)"
    echo "  install-wpcli-existing  - Install WP-CLI in existing container"
    echo "  redeploy-wordpress-with-wpcli - Redeploy with WP-CLI"
    echo ""
    echo "📁 Content Migration:"
    echo "  migrate-wordpress-content     - Migrate WordPress files (tar method)"
    echo "  migrate-wordpress-content-alt - Alternative migration (no tar)"
    echo "  migrate-wordpress-simple      - Simple migration method"
    echo "  migrate-database             - Database migration"
    echo ""
    echo "🔗 URL & Connectivity Fixes:"
    echo "  fix-wordpress-urls       - Fix WordPress URLs (remove :8080, set HTTPS)"
    echo "  fix-ingress-issues      - Fix ingress connectivity issues"
    echo "  update-wordpress-urls   - Basic URL updates"
    echo "  update-wordpress-urls-advanced - Advanced URL updates with WP-CLI"
    echo "  update-wordpress-urls-simple   - Simple URL updates"
    echo ""
    echo "🔍 Diagnostics & Monitoring:"
    echo "  diagnose-wordpress      - Comprehensive WordPress diagnostics"
    echo "  check-ingress-status   - Check ingress and service status"
    echo "  check-wordpress-urls   - Check current WordPress URLs"
    echo "  check-php-settings     - Check PHP upload and configuration settings"
    echo "  check-ssl-status       - Check SSL certificate status"
    echo "  monitor-php-fpm        - Monitor PHP-FPM processes and performance"
    echo "  verify-deployment      - Verify deployment status"
    echo "  monitor-wordpress      - Monitor WordPress deployment"
    echo ""
    echo "🧪 Testing & Utilities:"
    echo "  test-debian-packages   - Test available packages in container"
    echo "  test-tar-method       - Test tar method for file copying"
    echo ""
    echo "Examples:"
    echo "  ./run-script.sh master-deploy-wordpress"
    echo "  ./run-script.sh fix-wordpress-urls"
    echo "  ./run-script.sh diagnose-wordpress"
    echo ""
    exit 0
fi

# Remove .sh extension if provided
SCRIPT_NAME="${SCRIPT_NAME%.sh}"

SCRIPT_PATH="$SCRIPTS_DIR/$SCRIPT_NAME.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    log_error "Script not found: $SCRIPT_NAME"
    echo ""
    echo "Available scripts:"
    ls -1 "$SCRIPTS_DIR"/*.sh | xargs -n1 basename | sed 's/\.sh$//' | sort
    exit 1
fi

log_info "Running script: $SCRIPT_NAME"
log_info "Script path: $SCRIPT_PATH"
echo ""

# Change to scripts directory and run the script
cd "$SCRIPTS_DIR"
exec "./$SCRIPT_NAME.sh" "${@:2}"