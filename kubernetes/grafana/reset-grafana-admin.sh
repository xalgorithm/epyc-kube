#!/bin/bash

set -e

echo "Resetting Grafana admin credentials..."

# Apply the ConfigMap with admin credentials reset
kubectl apply -f grafana-admin-reset.yaml

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
            "name": "admin-reset",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "admin-reset",
          "configMap": {
            "name": "grafana-admin-reset"
          }
        }]
      }
    }
  }
}'

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

echo "Grafana admin credentials have been reset to:"
echo "Username: admin"
echo "Password: changeme123"
echo ""
echo "Try logging in to https://grafana.admin.im with these credentials." 