#!/bin/bash

# Apply Conservative EthosEnv Resource Increases
# Applies smaller resource increases that fit within cluster capacity

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="ethosenv"

echo -e "${BLUE}Applying Conservative EthosEnv Resource Increases${NC}"
echo -e "${BLUE}================================================${NC}"

# Check cluster resources first
echo -e "${YELLOW}Current Cluster Resource Usage:${NC}"
kubectl top nodes
echo ""

# Show current pod resources
echo -e "${YELLOW}Current EthosEnv Pod Resources:${NC}"
kubectl get pods -n $NAMESPACE -o wide
echo ""

# Show current deployment resources
echo -e "${YELLOW}Current Resource Allocations:${NC}"
echo -e "${BLUE}MySQL:${NC}"
kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'

echo -e "${BLUE}WordPress:${NC}"
kubectl get deployment wordpress -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'

echo ""

# Show proposed conservative changes
echo -e "${YELLOW}Proposed Conservative Resource Changes:${NC}"
echo ""
echo -e "${BLUE}MySQL (Current → New):${NC}"
echo -e "${YELLOW}  CPU Requests:  500m → 750m${NC}"
echo -e "${YELLOW}  CPU Limits:    1000m → 1200m${NC}"
echo -e "${YELLOW}  Memory Requests: 1Gi → 1.5Gi${NC}"
echo -e "${YELLOW}  Memory Limits:   2Gi → 3Gi${NC}"
echo ""
echo -e "${BLUE}WordPress (Current → New):${NC}"
echo -e "${YELLOW}  CPU Requests:  500m → 600m${NC}"
echo -e "${YELLOW}  CPU Limits:    1000m → 1200m${NC}"
echo -e "${YELLOW}  Memory Requests: 256Mi → 512Mi${NC}"
echo -e "${YELLOW}  Memory Limits:   512Mi → 1Gi${NC}"
echo ""

# Confirm with user
echo -e "${YELLOW}These are conservative increases designed to fit within cluster capacity.${NC}"
echo -e "${YELLOW}Do you want to proceed? (y/N):${NC}"
read -r confirm

if [[ $confirm =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Proceeding with conservative resource increases...${NC}"
    echo ""
    
    # Apply MySQL conservative patch
    echo -e "${YELLOW}Applying MySQL conservative resource increase...${NC}"
    if kubectl patch deployment mysql -n $NAMESPACE --patch-file kubernetes/ethosenv/mysql-resources-conservative.yaml; then
        echo -e "${GREEN}✓ MySQL conservative patch applied${NC}"
    else
        echo -e "${RED}✗ Failed to apply MySQL conservative patch${NC}"
        exit 1
    fi
    
    # Apply WordPress conservative patch
    echo -e "${YELLOW}Applying WordPress conservative resource increase...${NC}"
    if kubectl patch deployment wordpress -n $NAMESPACE --patch-file kubernetes/ethosenv/wordpress-resources-conservative.yaml; then
        echo -e "${GREEN}✓ WordPress conservative patch applied${NC}"
    else
        echo -e "${RED}✗ Failed to apply WordPress conservative patch${NC}"
        exit 1
    fi
    
    echo ""
    
    # Wait for rollouts with shorter timeout
    echo -e "${YELLOW}Waiting for deployment rollouts...${NC}"
    
    echo -e "${BLUE}MySQL rollout status:${NC}"
    if kubectl rollout status deployment/mysql -n $NAMESPACE --timeout=180s; then
        echo -e "${GREEN}✓ MySQL rollout completed${NC}"
    else
        echo -e "${YELLOW}⚠ MySQL rollout taking longer than expected${NC}"
    fi
    
    echo -e "${BLUE}WordPress rollout status:${NC}"
    if kubectl rollout status deployment/wordpress -n $NAMESPACE --timeout=180s; then
        echo -e "${GREEN}✓ WordPress rollout completed${NC}"
    else
        echo -e "${YELLOW}⚠ WordPress rollout taking longer than expected${NC}"
    fi
    
    echo ""
    
    # Show final status
    echo -e "${YELLOW}Final Pod Status:${NC}"
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
    
    # Verify new resources
    echo -e "${YELLOW}New Resource Allocations:${NC}"
    echo -e "${BLUE}MySQL:${NC}"
    kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
    
    echo -e "${BLUE}WordPress:${NC}"
    kubectl get deployment wordpress -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
    
    echo ""
    echo -e "${GREEN}🎉 Conservative EthosEnv resource increases applied successfully!${NC}"
    echo ""
    echo -e "${BLUE}Resource Summary:${NC}"
    echo -e "${GREEN}MySQL:     CPU 500m-1000m → 750m-1200m, Memory 1Gi-2Gi → 1.5Gi-3Gi${NC}"
    echo -e "${GREEN}WordPress: CPU 500m-1000m → 600m-1200m, Memory 256Mi-512Mi → 512Mi-1Gi${NC}"
    echo ""
    echo -e "${YELLOW}Note: These are conservative increases to fit within cluster capacity.${NC}"
    echo -e "${YELLOW}Monitor performance and consider cluster expansion for larger increases.${NC}"
    
else
    echo -e "${YELLOW}Resource allocation increase cancelled by user${NC}"
fi
