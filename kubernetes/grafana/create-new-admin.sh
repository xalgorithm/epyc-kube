#!/bin/bash

set -e

echo "Creating a new Grafana admin user..."

# Apply the ConfigMap with new admin user configuration
kubectl apply -f grafana-new-admin.yaml

# Update the Grafana deployment to use our ConfigMap
kubectl patch deployment -n monitoring kube-prometheus-stack-grafana --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "grafana",
          "volumeMounts": [{
            "mountPath": "/etc/grafana/grafana.ini",
            "name": "new-admin",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "new-admin",
          "configMap": {
            "name": "grafana-new-admin"
          }
        }]
      }
    }
  }
}'

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

echo "A new Grafana admin user has been created with the following credentials:"
echo "Username: grafana_admin"
echo "Password: <REDACTED_PASSWORD>"
echo ""
echo "Try logging in to https://grafana.gray-beard.com with these new credentials." 