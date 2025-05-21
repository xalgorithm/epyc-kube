#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Deploying n8n components..."

# Create namespace if not exists
kubectl get namespace n8n || kubectl create -f "$SCRIPT_DIR/namespace.yaml"

# Apply n8n components
kubectl apply -f "$SCRIPT_DIR/pvc.yaml"
kubectl apply -f "$SCRIPT_DIR/secret.yaml"
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/service.yaml"
kubectl apply -f "$SCRIPT_DIR/ingress-tls.yaml"
kubectl apply -f "$SCRIPT_DIR/servicemonitor.yaml"
kubectl apply -f "$SCRIPT_DIR/alertrule.yaml"
kubectl apply -f "$SCRIPT_DIR/grafana-dashboard-cm.yaml"

echo "n8n components deployed successfully."
echo "Waiting for pods to become ready..."

kubectl rollout status deployment -n n8n n8n

echo "All pods are ready. n8n is now available."
echo "Access n8n at https://automate.gray-beard.com" 