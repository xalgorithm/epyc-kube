#!/bin/bash

set -e

echo "Applying basic auth configuration to Grafana..."

# Apply the ConfigMap
kubectl apply -f reset-grafana-config.yaml

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
            "name": "basic-auth-config",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "basic-auth-config",
          "configMap": {
            "name": "grafana-basic-auth-config"
          }
        }]
      }
    }
  }
}'

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

echo "Basic auth configuration applied to Grafana."
echo "You should now be able to log in with username 'xalg' and password 'admin123.'" 