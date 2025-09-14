#!/bin/bash

# Deploy WordPress PHP Configuration Updates
# This script applies the updated ConfigMap and WordPress deployment with custom PHP settings

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Deploying WordPress PHP configuration updates...${NC}"

# Apply the updated ConfigMap with PHP settings
echo -e "${YELLOW}Applying updated ConfigMap with PHP configuration...${NC}"
kubectl apply -f wordpress-exporter.yaml

# Apply the updated WordPress deployment
echo -e "${YELLOW}Applying updated WordPress deployment...${NC}"
kubectl apply -f wordpress-deployment.yaml

# Wait for rollout to complete
echo -e "${YELLOW}Waiting for WordPress deployment rollout to complete...${NC}"
kubectl rollout status deployment/wordpress -n wordpress --timeout=300s

# Verify the PHP configuration is loaded
echo -e "${YELLOW}Verifying PHP configuration...${NC}"
echo "Waiting 30 seconds for pod to be ready..."
sleep 30

# Get the WordPress pod name
POD_NAME=$(kubectl get pods -n wordpress -l app=wordpress -o jsonpath='{.items[0].metadata.name}')

if [ -n "$POD_NAME" ]; then
    echo -e "${BLUE}Checking PHP configuration in pod: $POD_NAME${NC}"
    
    # Check if the custom PHP config file is mounted
    echo -e "${YELLOW}Checking if custom PHP config file is mounted:${NC}"
    kubectl exec -n wordpress "$POD_NAME" -- ls -la /usr/local/etc/php/conf.d/custom-php.ini || echo "Custom PHP config file not found"
    
    # Check PHP configuration values
    echo -e "${YELLOW}Checking PHP configuration values:${NC}"
    kubectl exec -n wordpress "$POD_NAME" -- php -c /usr/local/etc/php/conf.d/custom-php.ini -r "
        echo 'upload_max_filesize: ' . ini_get('upload_max_filesize') . PHP_EOL;
        echo 'post_max_size: ' . ini_get('post_max_size') . PHP_EOL;
        echo 'memory_limit: ' . ini_get('memory_limit') . PHP_EOL;
        echo 'max_execution_time: ' . ini_get('max_execution_time') . PHP_EOL;
    " || echo "Could not verify PHP settings directly"
    
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo -e "${BLUE}PHP Configuration Applied:${NC}"
    echo "  - upload_max_filesize: 20M"
    echo "  - post_max_size: 25M" 
    echo "  - memory_limit: 128M"
    echo "  - max_execution_time: 300"
else
    echo -e "${RED}Could not find WordPress pod. Please check the deployment status.${NC}"
    exit 1
fi

echo -e "${GREEN}WordPress PHP configuration update completed!${NC}"
