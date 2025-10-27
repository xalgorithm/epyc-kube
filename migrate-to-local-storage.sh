#!/bin/bash

# Migration script to move services from NFS to local storage
# This script will:
# 1. Scale down affected deployments/statefulsets
# 2. Delete problematic PVCs
# 3. Recreate them with local-path storage class
# 4. Scale services back up

set -e

KUBECONFIG_FILE="kubeconfig.yaml"

echo "🔄 Starting migration from NFS to local storage..."
echo "=================================================="

# Function to scale down a deployment
scale_down_deployment() {
    local namespace=$1
    local deployment=$2
    echo "📉 Scaling down deployment $namespace/$deployment"
    kubectl --kubeconfig=$KUBECONFIG_FILE scale deployment $deployment -n $namespace --replicas=0 || true
}

# Function to scale down a statefulset
scale_down_statefulset() {
    local namespace=$1
    local statefulset=$2
    echo "📉 Scaling down statefulset $namespace/$statefulset"
    kubectl --kubeconfig=$KUBECONFIG_FILE scale statefulset $statefulset -n $namespace --replicas=0 || true
}

# Function to delete a PVC and recreate with local storage
migrate_pvc() {
    local namespace=$1
    local pvc_name=$2
    local size=$3
    
    echo "🔄 Migrating PVC $namespace/$pvc_name"
    
    # Delete the old PVC
    kubectl --kubeconfig=$KUBECONFIG_FILE delete pvc $pvc_name -n $namespace --ignore-not-found=true
    
    # Wait a moment for cleanup
    sleep 2
    
    # Create new PVC with local-path storage class
    cat <<EOF | kubectl --kubeconfig=$KUBECONFIG_FILE apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc_name
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: $size
EOF
}

# Function to scale up a deployment
scale_up_deployment() {
    local namespace=$1
    local deployment=$2
    local replicas=${3:-1}
    echo "📈 Scaling up deployment $namespace/$deployment to $replicas replicas"
    kubectl --kubeconfig=$KUBECONFIG_FILE scale deployment $deployment -n $namespace --replicas=$replicas || true
}

# Function to scale up a statefulset
scale_up_statefulset() {
    local namespace=$1
    local statefulset=$2
    local replicas=${3:-1}
    echo "📈 Scaling up statefulset $namespace/$statefulset to $replicas replicas"
    kubectl --kubeconfig=$KUBECONFIG_FILE scale statefulset $statefulset -n $namespace --replicas=$replicas || true
}

echo ""
echo "🛑 Step 1: Scaling down affected services..."
echo "============================================="

# Scale down deployments
scale_down_deployment "automation" "activepieces"
scale_down_deployment "ethosenv" "mysql"
scale_down_deployment "ethosenv" "wordpress"
scale_down_deployment "kampfzwerg" "wordpress-mysql"
scale_down_deployment "kampfzwerg" "wordpress"
scale_down_deployment "keycloak" "keycloak"
scale_down_deployment "keycloak" "keycloak-postgres"
scale_down_deployment "n8n" "n8n"
scale_down_deployment "nfty" "nfty"
scale_down_deployment "obsidian" "couchdb"
scale_down_deployment "obsidian" "obsidian"
scale_down_deployment "vault" "vault"
scale_down_deployment "media" "mylar"

# Scale down statefulsets
scale_down_statefulset "automation" "activepieces-postgresql"
scale_down_statefulset "automation" "activepieces-redis-master"
scale_down_statefulset "airflow" "postgresql-primary"
scale_down_statefulset "airflow" "redis"

echo ""
echo "⏳ Waiting for pods to terminate..."
sleep 10

echo ""
echo "🗑️  Step 2: Migrating PVCs to local storage..."
echo "==============================================="

# Migrate PVCs - using smaller sizes for local storage to be more conservative
migrate_pvc "automation" "data-activepieces-postgresql-0" "5Gi"
migrate_pvc "automation" "redis-data-activepieces-redis-master-0" "2Gi"
migrate_pvc "automation" "activepieces-cache" "1Gi"
migrate_pvc "ethosenv" "mysql-pvc" "5Gi"
migrate_pvc "ethosenv" "wordpress-pvc" "2Gi"
migrate_pvc "kampfzwerg" "mysql-data" "5Gi"
migrate_pvc "kampfzwerg" "wordpress-data" "5Gi"
migrate_pvc "keycloak" "keycloak-data" "1Gi"
migrate_pvc "keycloak" "keycloak-postgres-data" "1Gi"
migrate_pvc "n8n" "n8n-data" "1Gi"
migrate_pvc "nfty" "nfty-data" "1Gi"
migrate_pvc "obsidian" "couchdb-data" "5Gi"
migrate_pvc "obsidian" "obsidian-config" "1Gi"
migrate_pvc "obsidian" "obsidian-vaults" "5Gi"
migrate_pvc "vault" "vault-data" "1Gi"

echo ""
echo "⏳ Waiting for PVCs to be bound..."
sleep 5

echo ""
echo "📈 Step 3: Scaling services back up..."
echo "======================================"

# Scale up deployments
scale_up_deployment "automation" "activepieces" 1
scale_up_deployment "ethosenv" "mysql" 1
scale_up_deployment "ethosenv" "wordpress" 1
scale_up_deployment "kampfzwerg" "wordpress-mysql" 1
scale_up_deployment "kampfzwerg" "wordpress" 1
scale_up_deployment "keycloak" "keycloak" 1
scale_up_deployment "keycloak" "keycloak-postgres" 1
scale_up_deployment "n8n" "n8n" 1
scale_up_deployment "nfty" "nfty" 1
scale_up_deployment "obsidian" "couchdb" 1
scale_up_deployment "obsidian" "obsidian" 1
scale_up_deployment "vault" "vault" 1
scale_up_deployment "media" "mylar" 1

# Scale up statefulsets
scale_up_statefulset "automation" "activepieces-postgresql" 1
scale_up_statefulset "automation" "activepieces-redis-master" 1

echo ""
echo "⏳ Waiting for services to start..."
sleep 15

echo ""
echo "🔍 Step 4: Checking service status..."
echo "====================================="

echo "Checking pod status:"
kubectl --kubeconfig=$KUBECONFIG_FILE get pods --all-namespaces | grep -E "(automation|ethosenv|kampfzwerg|keycloak|n8n|nfty|obsidian|vault|media)"

echo ""
echo "Checking PVC status:"
kubectl --kubeconfig=$KUBECONFIG_FILE get pvc --all-namespaces | grep local-path

echo ""
echo "✅ Migration completed!"
echo "======================"
echo ""
echo "📝 Next steps:"
echo "1. Monitor the services for a few minutes to ensure they start properly"
echo "2. Check logs if any services fail to start: kubectl logs <pod-name> -n <namespace>"
echo "3. Some services may need time to initialize their databases"
echo ""
echo "⚠️  Note: All data from the old NFS storage has been lost."
echo "   Services will start with fresh/empty databases."