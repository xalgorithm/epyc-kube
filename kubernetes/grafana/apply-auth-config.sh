#!/bin/bash

set -e

echo "Applying auth configuration to Grafana..."

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
            "name": "auth-config",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "auth-config",
          "configMap": {
            "name": "grafana-auth-config"
          }
        }]
      }
    }
  }
}'

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

echo "Auth configuration applied to Grafana."
echo "You should now be able to log in with the xalg user account." 