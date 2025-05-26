#!/bin/bash

set -e

echo "Creating a standard admin user in Grafana..."

# Create new admin password (very simple for testing)
NEW_ADMIN_USER="admin"
NEW_ADMIN_PASSWORD="admin"

# Encode credentials to base64
ADMIN_USER_B64=$(echo -n "$NEW_ADMIN_USER" | base64)
ADMIN_PASS_B64=$(echo -n "$NEW_ADMIN_PASSWORD" | base64)

# Update the secret with new credentials
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o json | \
  jq --arg user "$ADMIN_USER_B64" --arg pass "$ADMIN_PASS_B64" \
     '.data["admin-user"]=$user | .data["admin-password"]=$pass' | \
  kubectl apply -f -

# Create a simple grafana.ini config
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-simple-config
  namespace: monitoring
data:
  grafana.ini: |
    [security]
    admin_user = admin
    admin_password = admin
    disable_initial_admin_creation = false
    
    [auth]
    disable_login_form = false
    
    [auth.basic]
    enabled = true
    
    [users]
    allow_sign_up = false
EOF

# Apply the new config
kubectl patch deployment -n monitoring kube-prometheus-stack-grafana --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "grafana",
          "volumeMounts": [{
            "mountPath": "/etc/grafana/grafana.ini",
            "name": "simple-config",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "simple-config",
          "configMap": {
            "name": "grafana-simple-config"
          }
        }]
      }
    }
  }
}'

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