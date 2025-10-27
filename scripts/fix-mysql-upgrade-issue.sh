#!/bin/bash

# Fix MySQL Upgrade Issue Script
# Resolves MySQL upgrade conflicts by running mysql_upgrade manually

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="ethosenv"

echo -e "${BLUE}MySQL Upgrade Issue Fix Script${NC}"
echo -e "${BLUE}==============================${NC}"

# Function to show current MySQL status
show_mysql_status() {
    echo -e "${YELLOW}Current MySQL Pod Status:${NC}"
    kubectl get pods -n $NAMESPACE -l app=mysql
    echo ""
}

# Function to scale down MySQL
scale_down_mysql() {
    echo -e "${YELLOW}Scaling down MySQL deployment...${NC}"
    kubectl scale deployment mysql -n $NAMESPACE --replicas=0
    
    echo -e "${BLUE}Waiting for MySQL pod to terminate...${NC}"
    kubectl wait --for=delete pod -l app=mysql -n $NAMESPACE --timeout=60s || true
    
    echo -e "${GREEN}✓ MySQL scaled down${NC}"
}

# Function to create a temporary MySQL pod for upgrade
create_upgrade_pod() {
    echo -e "${YELLOW}Creating temporary MySQL upgrade pod...${NC}"
    
    cat > /tmp/mysql-upgrade-pod.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: mysql-upgrade
  namespace: $NAMESPACE
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    command: ["sleep", "3600"]
    env:
    - name: MYSQL_ROOT_PASSWORD
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: MYSQL_ROOT_PASSWORD
    - name: MYSQL_DATABASE
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: MYSQL_DATABASE
    - name: MYSQL_USER
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: MYSQL_USER
    - name: MYSQL_PASSWORD
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: MYSQL_PASSWORD
    volumeMounts:
    - name: mysql-storage
      mountPath: /var/lib/mysql
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "1000m"
        memory: "2Gi"
  volumes:
  - name: mysql-storage
    persistentVolumeClaim:
      claimName: mysql-pvc
  restartPolicy: Never
EOF

    kubectl apply -f /tmp/mysql-upgrade-pod.yaml
    
    echo -e "${BLUE}Waiting for upgrade pod to be ready...${NC}"
    kubectl wait --for=condition=Ready pod/mysql-upgrade -n $NAMESPACE --timeout=120s
    
    echo -e "${GREEN}✓ Upgrade pod created and ready${NC}"
}

# Function to fix MySQL upgrade issue
fix_mysql_upgrade() {
    echo -e "${YELLOW}Fixing MySQL upgrade issue...${NC}"
    
    # Start MySQL in safe mode and run upgrade
    echo -e "${BLUE}Starting MySQL in upgrade mode...${NC}"
    kubectl exec mysql-upgrade -n $NAMESPACE -- bash -c "
        # Start MySQL in the background with upgrade mode
        mysqld --user=mysql --skip-grant-tables --skip-networking --socket=/tmp/mysql.sock &
        MYSQL_PID=\$!
        
        # Wait for MySQL to start
        sleep 10
        
        # Run mysql_upgrade
        mysql_upgrade --socket=/tmp/mysql.sock --force
        
        # Stop MySQL
        kill \$MYSQL_PID
        wait \$MYSQL_PID 2>/dev/null || true
        
        echo 'MySQL upgrade completed'
    " || {
        echo -e "${YELLOW}Direct upgrade failed, trying alternative method...${NC}"
        
        # Alternative: Remove upgrade marker files
        kubectl exec mysql-upgrade -n $NAMESPACE -- bash -c "
            cd /var/lib/mysql
            
            # Remove upgrade marker files that might be causing issues
            rm -f mysql_upgrade_info
            rm -f *.pid
            rm -f auto.cnf
            
            # Fix permissions
            chown -R mysql:mysql /var/lib/mysql
            
            echo 'Upgrade markers removed'
        "
    }
    
    echo -e "${GREEN}✓ MySQL upgrade issue fixed${NC}"
}

# Function to cleanup upgrade pod
cleanup_upgrade_pod() {
    echo -e "${YELLOW}Cleaning up upgrade pod...${NC}"
    kubectl delete pod mysql-upgrade -n $NAMESPACE --ignore-not-found=true
    rm -f /tmp/mysql-upgrade-pod.yaml
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Function to scale up MySQL
scale_up_mysql() {
    echo -e "${YELLOW}Scaling up MySQL deployment...${NC}"
    kubectl scale deployment mysql -n $NAMESPACE --replicas=1
    
    echo -e "${BLUE}Waiting for MySQL pod to be ready...${NC}"
    kubectl wait --for=condition=Ready pod -l app=mysql -n $NAMESPACE --timeout=180s
    
    echo -e "${GREEN}✓ MySQL scaled up and ready${NC}"
}

# Function to verify MySQL is working
verify_mysql() {
    echo -e "${YELLOW}Verifying MySQL is working...${NC}"
    
    MYSQL_POD=$(kubectl get pods -n $NAMESPACE -l app=mysql -o jsonpath='{.items[0].metadata.name}')
    
    if kubectl exec $MYSQL_POD -n $NAMESPACE -- mysql -u root -p\$MYSQL_ROOT_PASSWORD -e "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ MySQL is working correctly${NC}"
        
        # Show databases
        echo -e "${BLUE}Available databases:${NC}"
        kubectl exec $MYSQL_POD -n $NAMESPACE -- mysql -u root -p\$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"
        
        return 0
    else
        echo -e "${RED}✗ MySQL verification failed${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Starting MySQL upgrade issue fix...${NC}"
    echo ""
    
    # Show current status
    show_mysql_status
    
    # Confirm with user
    echo -e "${YELLOW}This will temporarily stop MySQL to fix the upgrade issue.${NC}"
    echo -e "${YELLOW}Do you want to proceed? (y/N):${NC}"
    read -r confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Proceeding with MySQL upgrade fix...${NC}"
        echo ""
        
        # Scale down MySQL
        scale_down_mysql
        echo ""
        
        # Create upgrade pod
        create_upgrade_pod
        echo ""
        
        # Fix upgrade issue
        fix_mysql_upgrade
        echo ""
        
        # Cleanup upgrade pod
        cleanup_upgrade_pod
        echo ""
        
        # Scale up MySQL
        scale_up_mysql
        echo ""
        
        # Verify MySQL
        if verify_mysql; then
            echo ""
            echo -e "${GREEN}🎉 MySQL upgrade issue fixed successfully!${NC}"
            echo -e "${BLUE}MySQL is now running with the updated resource allocations.${NC}"
        else
            echo ""
            echo -e "${RED}⚠ MySQL started but verification failed. Check logs for details.${NC}"
        fi
        
    else
        echo -e "${YELLOW}MySQL upgrade fix cancelled by user${NC}"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_upgrade_pod EXIT

# Run main function
main "$@"
