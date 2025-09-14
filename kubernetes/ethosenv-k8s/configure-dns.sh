#!/bin/bash

# Configure DNS for ethosenv.gray-beard.com
# This script provides instructions and commands to configure DNS

set -euo pipefail

DOMAIN="ethos.gray-beard.com"
PARENT_DOMAIN="gray-beard.com"

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

echo "🌐 DNS Configuration for $DOMAIN"
echo "=================================="

# Get current Traefik ingress IP
log_info "Checking Traefik ingress controller IP..."
TRAEFIK_IP=$(kubectl get service traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -n "$TRAEFIK_IP" ]]; then
    log_success "Traefik external IP: $TRAEFIK_IP"
else
    log_error "Could not get Traefik external IP"
    log_info "Checking Traefik service status..."
    kubectl get service traefik -n kube-system
    exit 1
fi

# Check current DNS resolution
log_info "Checking current DNS resolution for $DOMAIN..."
CURRENT_IP=$(dig +short $DOMAIN 2>/dev/null || echo "")

if [[ -n "$CURRENT_IP" ]]; then
    if [[ "$CURRENT_IP" == "$TRAEFIK_IP" ]]; then
        log_success "DNS is already correctly configured!"
        log_info "Current IP: $CURRENT_IP"
        log_info "Required IP: $TRAEFIK_IP"
        echo ""
        log_info "You can proceed with the WordPress deployment."
        exit 0
    else
        log_warning "DNS is configured but pointing to wrong IP"
        log_info "Current IP: $CURRENT_IP"
        log_info "Required IP: $TRAEFIK_IP"
    fi
else
    log_warning "DNS is not configured for $DOMAIN"
fi

echo ""
log_info "📋 DNS Configuration Required:"
echo "Domain: $DOMAIN"
echo "Target IP: $TRAEFIK_IP"
echo "Record Type: A"

echo ""
log_info "🔧 AWS Route 53 Configuration:"
echo "Since $PARENT_DOMAIN is hosted on AWS Route 53, you need to:"
echo ""
echo "1. Log in to AWS Console"
echo "2. Go to Route 53 → Hosted Zones"
echo "3. Select the '$PARENT_DOMAIN' hosted zone"
echo "4. Create a new A record:"
echo "   - Name: ethos"
echo "   - Type: A"
echo "   - Value: $TRAEFIK_IP"
echo "   - TTL: 300 (5 minutes)"

echo ""
log_info "🖥️  AWS CLI Command (if you have AWS CLI configured):"
echo "aws route53 change-resource-record-sets --hosted-zone-id YOUR_ZONE_ID --change-batch '{
  \"Changes\": [{
    \"Action\": \"UPSERT\",
    \"ResourceRecordSet\": {
      \"Name\": \"$DOMAIN\",
      \"Type\": \"A\",
      \"TTL\": 300,
      \"ResourceRecords\": [{\"Value\": \"$TRAEFIK_IP\"}]
    }
  }]
}'"

echo ""
log_info "🔍 Verification Commands:"
echo "# Check DNS propagation (may take 5-15 minutes)"
echo "dig $DOMAIN"
echo "nslookup $DOMAIN"
echo ""
echo "# Test HTTP connectivity (after DNS propagates)"
echo "curl -I http://$DOMAIN"
echo ""
echo "# Check SSL certificate status (after deployment)"
echo "./check-ssl-status.sh"

echo ""
log_info "⏱️  Timeline:"
echo "1. Configure DNS A record (immediate)"
echo "2. Wait for DNS propagation (5-15 minutes)"
echo "3. Deploy WordPress with SSL (./deploy-wordpress.sh)"
echo "4. Wait for SSL certificate issuance (5-10 minutes)"
echo "5. Access https://$DOMAIN"

echo ""
log_warning "⚠️  Important Notes:"
echo "- DNS propagation can take 5-15 minutes"
echo "- SSL certificate issuance requires HTTP access on port 80"
echo "- Let's Encrypt will validate domain ownership via HTTP-01 challenge"
echo "- Make sure port 80 and 443 are accessible from the internet"

# Check if we can reach the Traefik IP
echo ""
log_info "🔍 Testing Traefik connectivity..."
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "http://$TRAEFIK_IP" >/dev/null 2>&1; then
    log_success "Traefik is accessible on HTTP"
else
    log_warning "Could not reach Traefik on HTTP (this may be normal if no default backend is configured)"
fi

if timeout 5 curl -s -k -o /dev/null -w "%{http_code}" "https://$TRAEFIK_IP" >/dev/null 2>&1; then
    log_success "Traefik is accessible on HTTPS"
else
    log_info "Traefik HTTPS not yet configured (normal before SSL certificate)"
fi