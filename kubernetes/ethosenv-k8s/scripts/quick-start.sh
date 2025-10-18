#!/bin/bash

# WordPress Kubernetes Quick Start
# This script provides a guided deployment of WordPress to Kubernetes

set -euo pipefail

NAMESPACE="ethosenv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🚀 WordPress Kubernetes Quick Start"
echo "===================================="

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

log_success "Prerequisites check passed!"

# Show deployment options
echo ""
log_info "Deployment Options:"
echo "1. Fresh deployment (new WordPress installation)"
echo "2. Migration deployment (migrate from existing Docker setup)"
echo "3. Verification only (check existing deployment)"
echo "4. Monitoring (watch deployment status)"

echo ""
read -p "Select option (1-4): " -r OPTION

case "$OPTION" in
    1)
        log_info "Starting fresh WordPress deployment..."
        
        echo ""
        log_warning "This will create a new WordPress installation."
        read -p "Continue? (y/N): " -r CONFIRM
        if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled."
            exit 0
        fi
        
        # Deploy WordPress
        log_info "Deploying WordPress to Kubernetes..."
        "$SCRIPT_DIR/deploy-wordpress.sh"
        
        # Verify deployment
        log_info "Verifying deployment..."
        "$SCRIPT_DIR/verify-deployment.sh"
        
        log_success "Fresh WordPress deployment completed!"
        ;;
        
    2)
        log_info "Starting migration deployment..."
        
        # Check if source exists
        if [ ! -d "$SCRIPT_DIR/../ethosenv" ]; then
            log_error "Source WordPress directory not found: $SCRIPT_DIR/../ethosenv"
            log_info "Please ensure the ethosenv directory exists with your WordPress content."
            exit 1
        fi
        
        echo ""
        log_warning "This will migrate your existing WordPress to Kubernetes."
        log_warning "Make sure you have backups of your data!"
        read -p "Continue? (y/N): " -r CONFIRM
        if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
            log_info "Migration cancelled."
            exit 0
        fi
        
        # Deploy WordPress infrastructure
        log_info "Deploying WordPress infrastructure..."
        "$SCRIPT_DIR/deploy-wordpress.sh"
        
        # Wait for deployment to be ready
        log_info "Waiting for deployment to be ready..."
        sleep 30
        
        # Migrate content
        log_info "Migrating WordPress content..."
        "$SCRIPT_DIR/migrate-wordpress-content.sh"
        
        # Migrate database
        log_info "Migrating database..."
        "$SCRIPT_DIR/migrate-database.sh" full-migration
        
        # Verify deployment
        log_info "Verifying migration..."
        "$SCRIPT_DIR/verify-deployment.sh"
        
        log_success "WordPress migration completed!"
        ;;
        
    3)
        log_info "Verifying existing deployment..."
        "$SCRIPT_DIR/verify-deployment.sh"
        ;;
        
    4)
        log_info "Starting deployment monitoring..."
        "$SCRIPT_DIR/monitor-wordpress.sh" watch
        ;;
        
    *)
        log_error "Invalid option selected."
        exit 1
        ;;
esac

echo ""
log_info "🔗 Useful Commands:"
echo "Access WordPress: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
echo "Monitor deployment: $SCRIPT_DIR/monitor-wordpress.sh"
echo "Check logs: kubectl logs -f deployment/wordpress -n $NAMESPACE"
echo "Database shell: kubectl exec -it deployment/mysql -n $NAMESPACE -- mysql -u root -proot_password wordpress"

echo ""
log_info "📚 Documentation:"
echo "Full documentation: $SCRIPT_DIR/README.md"
echo "Troubleshooting: Check pod logs and run verify-deployment.sh"

echo ""
log_success "🎉 WordPress Kubernetes deployment process completed!"