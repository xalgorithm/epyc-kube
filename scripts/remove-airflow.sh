#!/bin/bash

# Script to completely remove Airflow and all its dependencies
# This will remove all Airflow resources, PVCs, and data

set -e

KUBECONFIG_FILE="kubeconfig.yaml"
NAMESPACE="airflow"

echo "🗑️  Removing Airflow and all dependencies..."
echo "============================================="
echo ""
echo "⚠️  WARNING: This will permanently delete:"
echo "   - All Airflow pods, services, and deployments"
echo "   - All Airflow persistent volumes and data"
echo "   - Airflow ingress routes"
echo "   - PostgreSQL database with all Airflow data"
echo "   - Redis cache and all stored data"
echo ""

# Function to safely delete resources
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if kubectl --kubeconfig=$KUBECONFIG_FILE get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
        echo "🗑️  Deleting $resource_type: $resource_name"
        kubectl --kubeconfig=$KUBECONFIG_FILE delete $resource_type $resource_name -n $namespace --ignore-not-found=true
    fi
}

# Function to delete all resources of a type
delete_all_of_type() {
    local resource_type=$1
    local namespace=$2
    
    echo "🗑️  Deleting all $resource_type in namespace $namespace"
    kubectl --kubeconfig=$KUBECONFIG_FILE delete $resource_type --all -n $namespace --ignore-not-found=true
}

echo "📋 Step 1: Scaling down StatefulSets and Deployments..."
echo "======================================================="

# Scale down StatefulSets first to gracefully stop pods
kubectl --kubeconfig=$KUBECONFIG_FILE scale statefulset postgresql-primary -n $NAMESPACE --replicas=0 2>/dev/null || true
kubectl --kubeconfig=$KUBECONFIG_FILE scale statefulset redis -n $NAMESPACE --replicas=0 2>/dev/null || true

# Scale down deployments
kubectl --kubeconfig=$KUBECONFIG_FILE scale deployment redis-exporter -n $NAMESPACE --replicas=0 2>/dev/null || true

echo "⏳ Waiting for pods to terminate..."
sleep 10

echo ""
echo "📋 Step 2: Deleting Ingress resources..."
echo "========================================"

# Delete ingresses
safe_delete "ingress" "airflow-tls" $NAMESPACE
safe_delete "ingress" "cm-acme-http-solver-lk59t" $NAMESPACE

echo ""
echo "📋 Step 3: Deleting Services..."
echo "==============================="

# Delete services
delete_all_of_type "service" $NAMESPACE

echo ""
echo "📋 Step 4: Deleting Deployments and StatefulSets..."
echo "==================================================="

# Delete deployments and statefulsets
delete_all_of_type "deployment" $NAMESPACE
delete_all_of_type "statefulset" $NAMESPACE

echo ""
echo "📋 Step 5: Deleting remaining pods..."
echo "====================================="

# Force delete any remaining pods
delete_all_of_type "pod" $NAMESPACE

echo ""
echo "📋 Step 6: Deleting Persistent Volume Claims..."
echo "==============================================="

# Delete PVCs (this will delete all data!)
delete_all_of_type "pvc" $NAMESPACE

echo ""
echo "📋 Step 7: Deleting ConfigMaps and Secrets..."
echo "=============================================="

# Delete configmaps and secrets
delete_all_of_type "configmap" $NAMESPACE
delete_all_of_type "secret" $NAMESPACE

echo ""
echo "📋 Step 8: Cleaning up other resources..."
echo "========================================="

# Delete any remaining resources
delete_all_of_type "job" $NAMESPACE
delete_all_of_type "cronjob" $NAMESPACE
delete_all_of_type "replicaset" $NAMESPACE

echo ""
echo "📋 Step 9: Removing Helm releases (if any)..."
echo "=============================================="

# Check for Helm releases in the airflow namespace
if helm --kubeconfig=$KUBECONFIG_FILE list -n $NAMESPACE -q 2>/dev/null | grep -q .; then
    echo "Found Helm releases in $NAMESPACE namespace:"
    helm --kubeconfig=$KUBECONFIG_FILE list -n $NAMESPACE
    
    # Delete all Helm releases in the namespace
    for release in $(helm --kubeconfig=$KUBECONFIG_FILE list -n $NAMESPACE -q 2>/dev/null); do
        echo "🗑️  Deleting Helm release: $release"
        helm --kubeconfig=$KUBECONFIG_FILE uninstall $release -n $NAMESPACE
    done
else
    echo "No Helm releases found in $NAMESPACE namespace"
fi

echo ""
echo "📋 Step 10: Final cleanup..."
echo "============================"

# Wait for resources to be fully deleted
echo "⏳ Waiting for resources to be fully deleted..."
sleep 5

# Check if namespace is empty
echo "📊 Checking remaining resources in $NAMESPACE namespace:"
kubectl --kubeconfig=$KUBECONFIG_FILE get all -n $NAMESPACE 2>/dev/null || echo "No resources found (expected)"

echo ""
echo "📋 Step 11: Updating reverse proxy configuration..."
echo "=================================================="

# Remove airflow from nginx configuration
echo "🔧 Removing airflow.gray-beard.com from reverse proxy configuration..."

# SSH to the server and update nginx config
ssh -F ssh_config gimli "
    # Remove airflow.gray-beard.com from the server_name list
    sudo sed -i 's/airflow\.xalg\.im//g' /etc/nginx/sites-available/k8s-reverse-proxy
    sudo sed -i 's/  *airflow\.xalg\.im//g' /etc/nginx/sites-available/k8s-reverse-proxy
    
    # Clean up any double spaces or empty lines
    sudo sed -i 's/  */ /g' /etc/nginx/sites-available/k8s-reverse-proxy
    sudo sed -i '/^[[:space:]]*$/d' /etc/nginx/sites-available/k8s-reverse-proxy
    
    # Test nginx configuration
    sudo nginx -t && sudo systemctl reload nginx
"

echo ""
echo "✅ Airflow removal completed!"
echo "============================="
echo ""
echo "📊 Summary of what was removed:"
echo "   ✅ All Airflow pods and containers"
echo "   ✅ PostgreSQL database and all data"
echo "   ✅ Redis cache and all data"
echo "   ✅ All persistent volumes and storage"
echo "   ✅ Ingress routes for airflow.gray-beard.com"
echo "   ✅ All services and networking"
echo "   ✅ Removed from reverse proxy configuration"
echo ""
echo "🔧 Next steps:"
echo "   1. Update DNS to remove airflow.gray-beard.com record (optional)"
echo "   2. The airflow namespace still exists but is empty"
echo "   3. You can delete the namespace with: kubectl delete namespace $NAMESPACE"
echo ""
echo "💾 Note: All Airflow data has been permanently deleted and cannot be recovered."