#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBSIDIAN_DIR="$(dirname "$SCRIPT_DIR")"
cd "$OBSIDIAN_DIR"

echo "Deploying CouchDB and Obsidian monitoring components..."

# Create namespace if not exists
kubectl get namespace obsidian || kubectl create -f "$OBSIDIAN_DIR/obsidian-namespace.yaml"

# Apply CouchDB monitoring components
kubectl apply -f "$OBSIDIAN_DIR/couchdb-servicemonitor.yaml"
kubectl apply -f "$OBSIDIAN_DIR/couchdb-deployment.yaml"
kubectl apply -f "$OBSIDIAN_DIR/couchdb-service.yaml"
kubectl apply -f "$OBSIDIAN_DIR/couchdb-alertrule.yaml"
kubectl apply -f "$OBSIDIAN_DIR/couchdb-grafana-dashboard-cm.yaml"

# Apply Obsidian monitoring components
kubectl apply -f "$OBSIDIAN_DIR/obsidian-servicemonitor.yaml"
kubectl apply -f "$OBSIDIAN_DIR/obsidian-deployment.yaml"
kubectl apply -f "$OBSIDIAN_DIR/obsidian-alertrule.yaml"
kubectl apply -f "$OBSIDIAN_DIR/obsidian-grafana-dashboard-cm.yaml"
kubectl apply -f "$OBSIDIAN_DIR/promtail-config.yaml"

# Restart pods to apply changes
kubectl rollout restart deployment -n obsidian couchdb
kubectl rollout restart deployment -n obsidian obsidian

echo "Monitoring components deployed successfully."
echo "Waiting for pods to become ready..."

kubectl rollout status deployment -n obsidian couchdb
kubectl rollout status deployment -n obsidian obsidian

echo "All pods are ready. Monitoring is now active."
echo "Access Grafana dashboards at http://YOUR_GRAFANA_URL/dashboards" 