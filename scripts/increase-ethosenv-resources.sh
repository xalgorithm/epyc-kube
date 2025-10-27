#!/bin/bash

# EthosEnv Resource Allocation Increase Script
# Increases CPU and memory allocations for WordPress and MySQL deployments

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="ethosenv"

echo -e "${BLUE}EthosEnv Resource Allocation Increase${NC}"
echo -e "${BLUE}====================================${NC}"

# Function to show current resources
show_current_resources() {
    echo -e "${YELLOW}Current Resource Allocations:${NC}"
    echo ""
    
    echo -e "${BLUE}MySQL Deployment:${NC}"
    kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
    echo ""
    
    echo -e "${BLUE}WordPress Deployment:${NC}"
    kubectl get deployment wordpress -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
    echo ""
}

# Function to create resource patches
create_resource_patches() {
    echo -e "${YELLOW}Creating resource allocation patches...${NC}"
    
    # MySQL resource patch - Increase to 2 CPU cores and 4GB RAM
    cat > /tmp/mysql-resources-patch.yaml << EOF
spec:
  template:
    spec:
      containers:
      - name: mysql
        resources:
          requests:
            cpu: "1000m"
            memory: "2Gi"
          limits:
            cpu: "2000m"
            memory: "4Gi"
EOF

    # WordPress resource patch - Increase to 1.5 CPU cores and 2GB RAM
    cat > /tmp/wordpress-resources-patch.yaml << EOF
spec:
  template:
    spec:
      containers:
      - name: wordpress
        resources:
          requests:
            cpu: "750m"
            memory: "1Gi"
          limits:
            cpu: "1500m"
            memory: "2Gi"
EOF

    echo -e "${GREEN}✓ Resource patches created${NC}"
}

# Function to show proposed changes
show_proposed_changes() {
    echo -e "${YELLOW}Proposed Resource Changes:${NC}"
    echo ""
    
    echo -e "${BLUE}MySQL (Current → New):${NC}"
    echo -e "${YELLOW}  CPU Requests:  500m → 1000m${NC}"
    echo -e "${YELLOW}  CPU Limits:    1000m → 2000m${NC}"
    echo -e "${YELLOW}  Memory Requests: 1Gi → 2Gi${NC}"
    echo -e "${YELLOW}  Memory Limits:   2Gi → 4Gi${NC}"
    echo ""
    
    echo -e "${BLUE}WordPress (Current → New):${NC}"
    echo -e "${YELLOW}  CPU Requests:  500m → 750m${NC}"
    echo -e "${YELLOW}  CPU Limits:    1000m → 1500m${NC}"
    echo -e "${YELLOW}  Memory Requests: 256Mi → 1Gi${NC}"
    echo -e "${YELLOW}  Memory Limits:   512Mi → 2Gi${NC}"
    echo ""
}

# Function to apply resource patches
apply_resource_patches() {
    echo -e "${YELLOW}Applying resource allocation patches...${NC}"
    
    # Apply MySQL patch
    echo -e "${BLUE}Updating MySQL deployment...${NC}"
    if kubectl patch deployment mysql -n $NAMESPACE --patch-file /tmp/mysql-resources-patch.yaml; then
        echo -e "${GREEN}✓ MySQL resource patch applied${NC}"
    else
        echo -e "${RED}✗ Failed to apply MySQL resource patch${NC}"
        return 1
    fi
    
    # Apply WordPress patch
    echo -e "${BLUE}Updating WordPress deployment...${NC}"
    if kubectl patch deployment wordpress -n $NAMESPACE --patch-file /tmp/wordpress-resources-patch.yaml; then
        echo -e "${GREEN}✓ WordPress resource patch applied${NC}"
    else
        echo -e "${RED}✗ Failed to apply WordPress resource patch${NC}"
        return 1
    fi
}

# Function to wait for rollout completion
wait_for_rollout() {
    echo -e "${YELLOW}Waiting for deployment rollouts to complete...${NC}"
    
    echo -e "${BLUE}Waiting for MySQL rollout...${NC}"
    if kubectl rollout status deployment/mysql -n $NAMESPACE --timeout=300s; then
        echo -e "${GREEN}✓ MySQL rollout completed${NC}"
    else
        echo -e "${RED}✗ MySQL rollout failed or timed out${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Waiting for WordPress rollout...${NC}"
    if kubectl rollout status deployment/wordpress -n $NAMESPACE --timeout=300s; then
        echo -e "${GREEN}✓ WordPress rollout completed${NC}"
    else
        echo -e "${RED}✗ WordPress rollout failed or timed out${NC}"
        return 1
    fi
}

# Function to verify new resources
verify_new_resources() {
    echo -e "${YELLOW}Verifying new resource allocations...${NC}"
    echo ""
    
    echo -e "${BLUE}MySQL New Resources:${NC}"
    kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
    echo ""
    
    echo -e "${BLUE}WordPress New Resources:${NC}"
    kubectl get deployment wordpress -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
    echo ""
    
    # Check pod status
    echo -e "${BLUE}Pod Status:${NC}"
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
}

# Function to show resource usage
show_resource_usage() {
    echo -e "${YELLOW}Current Resource Usage:${NC}"
    echo ""
    
    # Get pod names
    MYSQL_POD=$(kubectl get pods -n $NAMESPACE -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    WORDPRESS_POD=$(kubectl get pods -n $NAMESPACE -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$MYSQL_POD" ]; then
        echo -e "${BLUE}MySQL Pod Resource Usage:${NC}"
        kubectl top pod $MYSQL_POD -n $NAMESPACE 2>/dev/null || echo "  Metrics not available"
    fi
    
    if [ -n "$WORDPRESS_POD" ]; then
        echo -e "${BLUE}WordPress Pod Resource Usage:${NC}"
        kubectl top pod $WORDPRESS_POD -n $NAMESPACE 2>/dev/null || echo "  Metrics not available"
    fi
    echo ""
}

# Function to cleanup temporary files
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -f /tmp/mysql-resources-patch.yaml /tmp/wordpress-resources-patch.yaml
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting EthosEnv resource allocation increase...${NC}"
    echo ""
    
    # Show current state
    show_current_resources
    
    # Create patches
    create_resource_patches
    
    # Show proposed changes
    show_proposed_changes
    
    # Confirm with user
    echo -e "${YELLOW}Do you want to proceed with these resource increases? (y/N):${NC}"
    read -r confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Proceeding with resource allocation increase...${NC}"
        echo ""
        
        # Apply patches
        apply_resource_patches
        echo ""
        
        # Wait for rollout
        wait_for_rollout
        echo ""
        
        # Verify new resources
        verify_new_resources
        
        # Show resource usage
        show_resource_usage
        
        echo -e "${GREEN}🎉 EthosEnv resource allocation increase completed successfully!${NC}"
        echo ""
        echo -e "${BLUE}Summary of Changes:${NC}"
        echo -e "${GREEN}✓ MySQL: CPU 500m-1000m → 1000m-2000m, Memory 1Gi-2Gi → 2Gi-4Gi${NC}"
        echo -e "${GREEN}✓ WordPress: CPU 500m-1000m → 750m-1500m, Memory 256Mi-512Mi → 1Gi-2Gi${NC}"
        
    else
        echo -e "${YELLOW}Resource allocation increase cancelled by user${NC}"
    fi
    
    # Cleanup
    cleanup
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
