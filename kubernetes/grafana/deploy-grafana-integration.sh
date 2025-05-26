#!/bin/bash

set -e

echo "Deploying Grafana-ntfy integration..."

# Apply the ntfy proxy deployment and service
kubectl apply -f grafana-ntfy-proxy.yaml

# Apply the Grafana contact point configurations
kubectl apply -f grafana-integration.yaml
kubectl apply -f direct-grafana-integration.yaml

# Apply the test alert rule
kubectl apply -f test-alert-rule.yaml

# Grafana admin password is set to a custom value
echo "Grafana admin password: changeme123"

echo "Integration deployed successfully!"
echo "To complete the setup:"
echo "1. Log in to Grafana at your Grafana URL with username 'admin' and the password above"
echo "2. Go to Alerting > Contact points"
echo "3. Verify that 'ntfy-alerts' contact point exists"
echo "4. Go to Alerting > Notification policies"
echo "5. Verify the route is configured correctly"
echo ""
echo "To test the integration, you can create a test alert rule in Grafana"
echo "or trigger an existing alert." 