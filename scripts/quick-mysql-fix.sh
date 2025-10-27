#!/bin/bash

# Quick MySQL Fix Script
# Simple approach to fix MySQL upgrade issue

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="ethosenv"

echo -e "${BLUE}Quick MySQL Fix${NC}"
echo -e "${BLUE}===============${NC}"

# Method 1: Add upgrade flag to deployment
fix_with_upgrade_flag() {
    echo -e "${YELLOW}Adding MySQL upgrade flag to deployment...${NC}"
    
    # Create patch to add upgrade command
    cat > /tmp/mysql-upgrade-patch.yaml << EOF
spec:
  template:
    spec:
      containers:
      - name: mysql
        command: ["docker-entrypoint.sh"]
        args: ["mysqld", "--upgrade=FORCE"]
EOF

    kubectl patch deployment mysql -n $NAMESPACE --patch-file /tmp/mysql-upgrade-patch.yaml
    
    echo -e "${GREEN}✓ Upgrade flag added${NC}"
    rm -f /tmp/mysql-upgrade-patch.yaml
}

# Method 2: Reset MySQL data directory permissions and upgrade markers
fix_with_data_reset() {
    echo -e "${YELLOW}Scaling down MySQL to fix data directory...${NC}"
    
    # Scale down
    kubectl scale deployment mysql -n $NAMESPACE --replicas=0
    kubectl wait --for=delete pod -l app=mysql -n $NAMESPACE --timeout=60s || true
    
    # Create temporary pod to fix data directory
    cat > /tmp/mysql-fix-pod.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: mysql-data-fix
  namespace: $NAMESPACE
spec:
  containers:
  - name: fix-container
    image: mysql:8.0
    command: ["sh", "-c"]
    args:
    - |
      echo "Fixing MySQL data directory..."
      cd /var/lib/mysql
      
      # Remove upgrade marker files
      rm -f mysql_upgrade_info
      rm -f *.pid
      rm -f auto.cnf
      
      # Fix ownership
      chown -R mysql:mysql /var/lib/mysql
      
      echo "Data directory fixed"
      sleep 30
    volumeMounts:
    - name: mysql-storage
      mountPath: /var/lib/mysql
  volumes:
  - name: mysql-storage
    persistentVolumeClaim:
      claimName: mysql-pvc
  restartPolicy: Never
EOF

    kubectl apply -f /tmp/mysql-fix-pod.yaml
    kubectl wait --for=condition=Ready pod/mysql-data-fix -n $NAMESPACE --timeout=60s
    
    # Wait for fix to complete
    sleep 35
    
    # Cleanup
    kubectl delete pod mysql-data-fix -n $NAMESPACE
    rm -f /tmp/mysql-fix-pod.yaml
    
    # Scale back up
    kubectl scale deployment mysql -n $NAMESPACE --replicas=1
    
    echo -e "${GREEN}✓ Data directory fixed${NC}"
}

# Method 3: Rollback to previous working deployment
rollback_deployment() {
    echo -e "${YELLOW}Rolling back MySQL deployment...${NC}"
    
    kubectl rollout undo deployment/mysql -n $NAMESPACE
    kubectl rollout status deployment/mysql -n $NAMESPACE --timeout=120s
    
    echo -e "${GREEN}✓ Deployment rolled back${NC}"
}

# Show current status
echo -e "${YELLOW}Current MySQL Status:${NC}"
kubectl get pods -n $NAMESPACE -l app=mysql
echo ""

# Show the error
echo -e "${YELLOW}MySQL Error Details:${NC}"
MYSQL_POD=$(kubectl get pods -n $NAMESPACE -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MYSQL_POD" ]; then
    kubectl logs $MYSQL_POD -n $NAMESPACE --tail=5 2>/dev/null || echo "No logs available"
fi
echo ""

echo -e "${YELLOW}Choose a fix method:${NC}"
echo "1. Add upgrade flag (recommended)"
echo "2. Reset data directory"
echo "3. Rollback deployment"
echo "4. Exit"
echo ""
echo -n "Enter choice (1-4): "
read -r choice

case $choice in
    1)
        fix_with_upgrade_flag
        ;;
    2)
        fix_with_data_reset
        ;;
    3)
        rollback_deployment
        ;;
    4)
        echo "Exiting without changes"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}Waiting for MySQL to be ready...${NC}"
kubectl rollout status deployment/mysql -n $NAMESPACE --timeout=180s

echo ""
echo -e "${YELLOW}Final MySQL Status:${NC}"
kubectl get pods -n $NAMESPACE -l app=mysql

# Test MySQL connection
echo ""
echo -e "${BLUE}Testing MySQL connection...${NC}"
MYSQL_POD=$(kubectl get pods -n $NAMESPACE -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MYSQL_POD" ]; then
    if kubectl exec $MYSQL_POD -n $NAMESPACE -- mysqladmin ping -h localhost >/dev/null 2>&1; then
        echo -e "${GREEN}✓ MySQL is responding to ping${NC}"
    else
        echo -e "${YELLOW}⚠ MySQL not responding yet, may need more time${NC}"
    fi
fi

echo ""
echo -e "${GREEN}🎉 MySQL fix attempt completed!${NC}"
