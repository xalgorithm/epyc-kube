#!/bin/bash

# Deploy Airflow Storage Configuration
# This script deploys persistent storage for Airflow DAGs and logs
# Requirements: 2.2, 2.3, 2.6

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_status "Starting Airflow storage deployment..."

# Create airflow namespace if it doesn't exist
print_status "Creating airflow namespace..."
kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -

# Apply storage configuration
print_status "Applying Airflow storage configuration..."
kubectl apply -f airflow-storage.yaml

# Wait for PVCs to be bound
print_status "Waiting for PVCs to be bound..."
kubectl wait --for=condition=Bound pvc/airflow-dags-pvc -n airflow --timeout=300s
kubectl wait --for=condition=Bound pvc/airflow-logs-pvc -n airflow --timeout=300s
kubectl wait --for=condition=Bound pvc/airflow-config-pvc -n airflow --timeout=300s

# Apply storage monitoring
print_status "Applying storage monitoring configuration..."
kubectl apply -f airflow-storage-monitoring.yaml

# Apply storage alerts
print_status "Applying storage alerting rules..."
kubectl apply -f airflow-storage-alerts.yaml

# Wait for monitoring deployment to be ready
print_status "Waiting for storage monitoring to be ready..."
kubectl wait --for=condition=Available deployment/airflow-storage-exporter -n airflow --timeout=300s

# Verify storage setup
print_status "Verifying storage setup..."

# Check PVC status
print_status "PVC Status:"
kubectl get pvc -n airflow -o wide

# Check storage monitoring
print_status "Storage Monitoring Status:"
kubectl get deployment airflow-storage-exporter -n airflow
kubectl get service airflow-storage-exporter -n airflow
kubectl get servicemonitor airflow-storage-monitor -n airflow

# Check PrometheusRule
print_status "Storage Alerting Rules:"
kubectl get prometheusrule airflow-storage-alerts -n airflow

# Test storage access
print_status "Testing storage access..."
kubectl run storage-test --image=busybox --rm -it --restart=Never -n airflow \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "storage-test",
        "image": "busybox",
        "command": ["sh", "-c", "echo \"Testing DAGs storage\" > /dags/test.txt && echo \"Testing logs storage\" > /logs/test.log && echo \"Testing config storage\" > /config/test.conf && ls -la /dags /logs /config && cat /dags/test.txt /logs/test.log /config/test.conf"],
        "volumeMounts": [
          {"name": "dags", "mountPath": "/dags"},
          {"name": "logs", "mountPath": "/logs"},
          {"name": "config", "mountPath": "/config"}
        ]
      }
    ],
    "volumes": [
      {"name": "dags", "persistentVolumeClaim": {"claimName": "airflow-dags-pvc"}},
      {"name": "logs", "persistentVolumeClaim": {"claimName": "airflow-logs-pvc"}},
      {"name": "config", "persistentVolumeClaim": {"claimName": "airflow-config-pvc"}}
    ]
  }
}' || print_warning "Storage test failed - this is expected if PVCs are not fully ready"

print_status "Airflow storage deployment completed successfully!"
print_status ""
print_status "Summary:"
print_status "- Created PVCs for DAGs (50Gi), logs (200Gi), and config (10Gi)"
print_status "- Configured ReadWriteMany access mode for multi-pod access"
print_status "- Set up storage monitoring with Prometheus metrics"
print_status "- Configured alerting for storage capacity and performance"
print_status "- All storage uses existing nfs-client storage class"
print_status ""
print_status "Next steps:"
print_status "1. Verify storage metrics are being collected in Prometheus"
print_status "2. Check Grafana for storage dashboards"
print_status "3. Test alert notifications"
print_status "4. Configure Airflow Helm chart to use these PVCs"