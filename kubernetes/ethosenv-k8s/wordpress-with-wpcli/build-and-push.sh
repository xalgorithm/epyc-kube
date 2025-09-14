#!/bin/bash

# Build and push WordPress with WP-CLI image

set -euo pipefail

# Configuration
IMAGE_NAME="wordpress-wpcli"
TAG="latest"
REGISTRY="your-registry.com"  # Change this to your container registry

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🐳 Building WordPress with WP-CLI Docker Image"

# Build the image
log_info "Building Docker image..."
docker build -t "${IMAGE_NAME}:${TAG}" .

if [ $? -eq 0 ]; then
    log_success "✅ Image built successfully: ${IMAGE_NAME}:${TAG}"
else
    log_error "❌ Failed to build image"
    exit 1
fi

# Test the image
log_info "Testing WP-CLI in the image..."
docker run --rm "${IMAGE_NAME}:${TAG}" wp --info --allow-root

if [ $? -eq 0 ]; then
    log_success "✅ WP-CLI is working in the image"
else
    log_error "❌ WP-CLI test failed"
    exit 1
fi

# Optional: Push to registry
read -p "Push to registry? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Tagging for registry..."
    docker tag "${IMAGE_NAME}:${TAG}" "${REGISTRY}/${IMAGE_NAME}:${TAG}"
    
    log_info "Pushing to registry..."
    docker push "${REGISTRY}/${IMAGE_NAME}:${TAG}"
    
    if [ $? -eq 0 ]; then
        log_success "✅ Image pushed to registry: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
        echo ""
        log_info "📝 To use this image, update your deployment:"
        echo "image: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    else
        log_error "❌ Failed to push image"
        exit 1
    fi
else
    log_info "Image built locally: ${IMAGE_NAME}:${TAG}"
    echo ""
    log_info "📝 To use this image locally, update your deployment:"
    echo "image: ${IMAGE_NAME}:${TAG}"
    echo "imagePullPolicy: Never"
fi

echo ""
log_success "🎉 WordPress with WP-CLI image ready!"