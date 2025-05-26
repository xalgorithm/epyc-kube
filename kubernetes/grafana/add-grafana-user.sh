#!/bin/bash

set -e

echo "Adding new user 'xalg' to Grafana..."

# Apply the ConfigMap with user configuration
kubectl apply -f add-grafana-user.yaml

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
            "name": "add-user",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "add-user",
          "configMap": {
            "name": "grafana-add-user"
          }
        }]
      }
    }
  }
}'

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

echo "New Grafana user has been added with the following credentials:"
echo "Username: xalg"
echo "Password: admin123."
echo ""
echo "Try logging in to https://grafana.gray-beard.com with these credentials." 