#!/bin/bash

# Apply EthosEnv Resource Increases
# Quick script to apply resource allocation increases

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="ethosenv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}Applying EthosEnv Resource Increases${NC}"
echo -e "${BLUE}===================================${NC}"

# Show current resources
echo -e "${YELLOW}Current Resources:${NC}"
echo -e "${BLUE}MySQL:${NC}"
kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq -r 'to_entries[] | "\(.key): \(.value | to_entries[] | "\(.key)=\(.value)")"' 2>/dev/null || echo "Unable to parse current MySQL resources"

echo -e "${BLUE}WordPress:${NC}"
kubectl get deployment wordpress -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq -r 'to_entries[] | "\(.key): \(.value | to_entries[] | "\(.key)=\(.value)")"' 2>/dev/null || echo "Unable to parse current WordPress resources"

echo ""

# Apply MySQL resource patch
echo -e "${YELLOW}Applying MySQL resource increase...${NC}"
if kubectl patch deployment mysql -n $NAMESPACE --patch-file "$MANIFEST_DIR/mysql-resources-patch.yaml"; then
    echo -e "${GREEN}✓ MySQL resource patch applied${NC}"
else
    echo -e "${RED}✗ Failed to apply MySQL resource patch${NC}"
    exit 1
fi

# Apply WordPress resource patch
echo -e "${YELLOW}Applying WordPress resource increase...${NC}"
if kubectl patch deployment wordpress -n $NAMESPACE --patch-file "$MANIFEST_DIR/wordpress-resources-patch.yaml"; then
    echo -e "${GREEN}✓ WordPress resource patch applied${NC}"
else
    echo -e "${RED}✗ Failed to apply WordPress resource patch${NC}"
    exit 1
fi

echo ""

# Wait for rollouts
echo -e "${YELLOW}Waiting for deployment rollouts...${NC}"

echo -e "${BLUE}MySQL rollout status:${NC}"
kubectl rollout status deployment/mysql -n $NAMESPACE --timeout=300s

echo -e "${BLUE}WordPress rollout status:${NC}"
kubectl rollout status deployment/wordpress -n $NAMESPACE --timeout=300s

echo ""

# Verify new resources
echo -e "${YELLOW}New Resource Allocations:${NC}"
echo -e "${BLUE}MySQL:${NC}"
kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'

echo -e "${BLUE}WordPress:${NC}"
kubectl get deployment wordpress -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'

echo ""

# Show pod status
echo -e "${YELLOW}Pod Status:${NC}"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo -e "${GREEN}🎉 EthosEnv resource increases applied successfully!${NC}"
echo ""
echo -e "${BLUE}Resource Summary:${NC}"
echo -e "${GREEN}MySQL:     CPU 500m-1000m → 1000m-2000m, Memory 1Gi-2Gi → 2Gi-4Gi${NC}"
echo -e "${GREEN}WordPress: CPU 500m-1000m → 750m-1500m, Memory 256Mi-512Mi → 1Gi-2Gi${NC}"
