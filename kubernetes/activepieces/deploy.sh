#!/bin/bash
set -e

echo "=== Activepieces Deployment Script ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Generate secrets if not already set
echo -e "${YELLOW}Generating secrets...${NC}"
ENCRYPTION_KEY=$(openssl rand -hex 16)  # Must be 32 hex chars (16 bytes)
JWT_SECRET=$(openssl rand -base64 32)
DB_PASSWORD=$(openssl rand -base64 24)

echo -e "${GREEN}✓ Secrets generated${NC}"
echo ""

# Create temporary file with secrets
TEMP_FILE=$(mktemp)
cp activepieces-complete.yaml "$TEMP_FILE"

# Replace placeholders
sed -i.bak "s|AP_ENCRYPTION_KEY:.*|AP_ENCRYPTION_KEY: \"$ENCRYPTION_KEY\"|" "$TEMP_FILE"
sed -i.bak "s|AP_JWT_SECRET:.*|AP_JWT_SECRET: \"$JWT_SECRET\"|" "$TEMP_FILE"
sed -i.bak "s|POSTGRES_PASSWORD:.*|POSTGRES_PASSWORD: \"$DB_PASSWORD\"|" "$TEMP_FILE"

echo -e "${YELLOW}Deploying Activepieces...${NC}"
kubectl apply -f "$TEMP_FILE"

# Clean up
rm -f "$TEMP_FILE" "$TEMP_FILE.bak"

echo ""
echo -e "${GREEN}✓ Deployment initiated${NC}"
echo ""
echo "Waiting for resources to be created..."
sleep 5

echo ""
echo "=== Checking Deployment Status ==="
echo ""

# Wait for deployments
echo -e "${YELLOW}Waiting for PostgreSQL...${NC}"
kubectl rollout status deployment/postgres -n automation --timeout=5m

echo -e "${YELLOW}Waiting for Redis...${NC}"
kubectl rollout status deployment/redis -n automation --timeout=5m

echo -e "${YELLOW}Waiting for Activepieces...${NC}"
kubectl rollout status deployment/activepieces -n automation --timeout=5m

echo ""
echo -e "${GREEN}=== Deployment Complete! ===${NC}"
echo ""

# Display status
echo "Current status:"
kubectl get pods -n automation
echo ""

echo "Ingress:"
kubectl get ingress -n automation
echo ""

echo -e "${GREEN}✓ Activepieces is deployed!${NC}"
echo ""
echo "Access your instance at: ${GREEN}https://automate2.gray-beard.com${NC}"
echo ""
echo "Generated credentials saved in secrets:"
echo "  - Encryption Key: (stored in activepieces-secrets)"
echo "  - JWT Secret: (stored in activepieces-secrets)"
echo "  - Database Password: (stored in activepieces-secrets)"
echo ""
echo "To view secrets:"
echo "  kubectl get secret activepieces-secrets -n automation -o yaml"
echo ""
echo "To view logs:"
echo "  kubectl logs -n automation deployment/activepieces -f"
echo ""

