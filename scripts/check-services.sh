#!/bin/bash

# Health check script for all services
# This script checks if all your services are responding correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Checking health of all services..."
echo "=================================="

# List of services to check
declare -A SERVICES=(
    ["Grafana"]="https://grafana.gray-beard.com"
    ["Airflow"]="https://airflow.gray-beard.com"
    ["N8N (automate)"]="https://automate.gray-beard.com"
    ["Activepieces (automate2)"]="https://automate2.gray-beard.com"
    ["Ethos WordPress"]="https://ethos.gray-beard.com"
    ["Kampfzwerg"]="https://kampfzwerg.gray-beard.com"
    ["Keycloak"]="https://login.gray-beard.com"
    ["Ntfy"]="https://notify.gray-beard.com"
    ["Obsidian"]="https://blackrock.gray-beard.com"
    ["CouchDB"]="https://couchdb.blackrock.gray-beard.com"
    ["Vault"]="https://vault.gray-beard.com"
)

# Check each service
for service in "${!SERVICES[@]}"; do
    url="${SERVICES[$service]}"
    echo -n "Checking $service ($url)... "
    
    # Use curl to check if the service responds
    if curl -s -k -L --max-time 10 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi
done

echo ""
echo "🔧 Checking Kubernetes backend services..."
echo "=========================================="

# Check Kubernetes NodePorts directly
K8S_NODES=("10.0.1.211" "10.0.1.212" "10.0.1.213")

for node in "${K8S_NODES[@]}"; do
    echo -n "Checking K8s node $node:30443... "
    if curl -s -k --max-time 5 "https://$node:30443" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi
done

echo ""
echo "📊 Nginx status:"
echo "================"
systemctl status nginx --no-pager -l

echo ""
echo "🔍 Recent nginx error logs:"
echo "==========================="
tail -n 10 /var/log/nginx/error.log 2>/dev/null || echo "No recent errors"