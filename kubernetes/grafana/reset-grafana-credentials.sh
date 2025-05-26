#!/bin/bash

set -e

echo "Resetting Grafana credentials in Kubernetes Secret..."

# Create new admin password
NEW_ADMIN_USER="xalg"
NEW_ADMIN_PASSWORD="admin123."

# Encode credentials to base64
ADMIN_USER_B64=$(echo -n "$NEW_ADMIN_USER" | base64)
ADMIN_PASS_B64=$(echo -n "$NEW_ADMIN_PASSWORD" | base64)

# Update the secret with new credentials
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o json | \
  jq --arg user "$ADMIN_USER_B64" --arg pass "$ADMIN_PASS_B64" \
     '.data["admin-user"]=$user | .data["admin-password"]=$pass' | \
  kubectl apply -f -

# Restart the Grafana pod to apply the changes
kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

echo "Grafana credentials have been reset to:"
echo "Username: $NEW_ADMIN_USER"
echo "Password: $NEW_ADMIN_PASSWORD"
echo ""
echo "Try logging in to https://grafana.gray-beard.com with these credentials." 