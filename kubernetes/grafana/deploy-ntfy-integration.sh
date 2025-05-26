#!/bin/bash

set -e

echo "Deploying ntfy integration for Grafana monitoring stack..."

# Apply the ConfigMaps
kubectl apply -f ntfy-integration.yaml
kubectl apply -f grafana-ntfy-templates.yaml

# Make the integration script executable
chmod +x grafana-ntfy-integration.sh

# Create or update the provisioning ConfigMap for Grafana
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-ntfy-provisioning
  namespace: monitoring
data:
  notifiers.yaml: |
    apiVersion: 1
    notifiers:
      - name: ntfy-general
        type: webhook
        uid: ntfy-general
        org_id: 1
        is_default: true
        send_reminder: true
        frequency: 1h
        disable_resolve_message: false
        settings:
          url: https://notify.gray-beard.com/monitoring-alerts
          httpMethod: POST
      - name: ntfy-critical
        type: webhook
        uid: ntfy-critical
        org_id: 1
        is_default: false
        send_reminder: true
        frequency: 15m
        disable_resolve_message: false
        settings:
          url: https://notify.gray-beard.com/critical-alerts
          httpMethod: POST
          httpHeaders:
            Priority: urgent
            Tags: warning,critical,alert
EOF

# Patch the Grafana deployment to mount the templates and provisioning
kubectl patch deployment -n monitoring kube-prometheus-stack-grafana --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "grafana",
            "volumeMounts": [
              {
                "mountPath": "/etc/grafana/provisioning/notifiers",
                "name": "ntfy-provisioning"
              },
              {
                "mountPath": "/etc/grafana/templates/ntfy",
                "name": "ntfy-templates"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "ntfy-provisioning",
            "configMap": {
              "name": "grafana-ntfy-provisioning"
            }
          },
          {
            "name": "ntfy-templates",
            "configMap": {
              "name": "grafana-ntfy-templates"
            }
          }
        ]
      }
    }
  }
}'

# Wait for the rollout to complete
echo "Waiting for Grafana to restart..."
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

# Now run the integration script to set up the ntfy contact points and routes
./grafana-ntfy-integration.sh

echo "====================================================="
echo "ntfy integration deployment complete!"
echo "====================================================="
echo ""
echo "Your monitoring system will now send alerts to ntfy at:"
echo "- Regular alerts: https://notify.gray-beard.com/monitoring-alerts"
echo "- Critical alerts: https://notify.gray-beard.com/critical-alerts"
echo ""
echo "To receive notifications:"
echo "1. Install the ntfy app on your mobile device from Google Play or F-Droid"
echo "2. Subscribe to the 'monitoring-alerts' and 'critical-alerts' topics"
echo "3. You can also access notifications via web browser at https://notify.gray-beard.com"
echo ""
echo "To test the integration, create a test alert in Grafana or run:"
echo "curl -d \"Test alert from monitoring system\" https://notify.gray-beard.com/monitoring-alerts"
echo ""
echo "Note: Critical alerts will have high priority and trigger more intrusive notifications" 