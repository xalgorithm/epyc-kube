#!/bin/bash
set -e

# ANSI color codes
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BLUE}Keycloak Deployment Script${NC}"
echo "This script will deploy Keycloak to your Kubernetes cluster."
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl could not be found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if the keycloak-secret.yaml file exists
if [ ! -f kubernetes/keycloak/keycloak-secret.yaml ]; then
    echo -e "${YELLOW}Keycloak secret file not found. Running setup script...${NC}"
    
    # Make the setup script executable
    chmod +x kubernetes/keycloak/setup-keycloak-vault.sh
    
    # Run the setup script
    ./kubernetes/keycloak/setup-keycloak-vault.sh
    
    # Check if the script was successful
    if [ ! -f kubernetes/keycloak/keycloak-secret.yaml ]; then
        echo -e "${RED}Failed to create Keycloak secret file. Exiting.${NC}"
        exit 1
    fi
fi

# Create namespace
echo -e "${BLUE}Creating Keycloak namespace...${NC}"
kubectl apply -f kubernetes/keycloak/namespace.yaml

# Apply secrets
echo -e "${BLUE}Applying Keycloak secrets...${NC}"
kubectl apply -f kubernetes/keycloak/keycloak-secret.yaml

# Apply PVCs
echo -e "${BLUE}Creating persistent volume claims...${NC}"
kubectl apply -f kubernetes/keycloak/pvc.yaml

# Apply PostgreSQL deployment
echo -e "${BLUE}Deploying PostgreSQL database...${NC}"
kubectl apply -f kubernetes/keycloak/postgres.yaml

# Wait for PostgreSQL to be ready
echo -e "${BLUE}Waiting for PostgreSQL to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/keycloak-postgres -n keycloak

# Apply Keycloak deployment
echo -e "${BLUE}Deploying Keycloak...${NC}"
kubectl apply -f kubernetes/keycloak/deployment.yaml

# Wait for Keycloak to be ready
echo -e "${BLUE}Waiting for Keycloak to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/keycloak -n keycloak

# Apply Ingress
echo -e "${BLUE}Creating Ingress for Keycloak...${NC}"
kubectl apply -f kubernetes/keycloak/ingress.yaml

echo -e "${GREEN}Keycloak deployment complete!${NC}"
echo -e "${YELLOW}Keycloak is now accessible at:${NC} https://login.gray-beard.com"
echo
echo -e "${YELLOW}Note:${NC} It may take a few minutes for DNS propagation and Let's Encrypt certificate issuance." 