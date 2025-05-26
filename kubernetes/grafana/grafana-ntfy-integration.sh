#!/bin/bash

set -e

echo "Setting up ntfy as the default notification mechanism for Grafana..."

# Create our ntfy topics
MONITORING_TOPIC="monitoring-alerts"
CRITICAL_TOPIC="critical-alerts"

# Wait a moment for pod to be stable after restart
echo "Waiting for Grafana pod to stabilize..."
sleep 10

# Get the Grafana pod name - use the most recent pod
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
echo "Using Grafana pod: $GRAFANA_POD"

# Get credentials securely from Vault
if command -v vault &> /dev/null && [ -n "$VAULT_ADDR" ] && [ -n "$VAULT_TOKEN" ]; then
  echo "Using Vault to retrieve credentials..."
  ADMIN_USER=$(vault kv get -field=username secret/grafana/admin)
  ADMIN_PASSWORD=$(vault kv get -field=password secret/grafana/admin)
else
  echo "Vault not configured. Using the Kubernetes secret to retrieve credentials..."
  ADMIN_USER=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-user}" | base64 --decode)
  ADMIN_PASSWORD=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
fi

# Create a port-forward to the Grafana pod
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring $GRAFANA_POD 3000:3000 &
PORT_FORWARD_PID=$!

# Wait for port-forward to establish
echo "Waiting for port-forward to establish..."
sleep 10

# Create the ntfy contact point
echo "Creating ntfy contact points in Grafana..."
cat > ntfy-contact-point.json << EOF
{
  "name": "ntfy-alerts",
  "type": "webhook",
  "settings": {
    "url": "https://notify.gray-beard.com/$MONITORING_TOPIC",
    "httpMethod": "POST",
    "username": "",
    "password": "",
    "authorization_scheme": "",
    "authorization_credentials": "",
    "maxAlerts": "5"
  },
  "disableResolveMessage": false
}
EOF

# Create a critical alerts contact point
cat > ntfy-critical-contact-point.json << EOF
{
  "name": "ntfy-critical-alerts",
  "type": "webhook",
  "settings": {
    "url": "https://notify.gray-beard.com/$CRITICAL_TOPIC",
    "httpMethod": "POST",
    "httpHeaders": {
      "Priority": "urgent",
      "Tags": "warning,critical,alert"
    },
    "username": "",
    "password": "",
    "authorization_scheme": "",
    "authorization_credentials": "",
    "maxAlerts": "5"
  },
  "disableResolveMessage": false
}
EOF

# Create contact points using Grafana API
echo "Adding ntfy contact points to Grafana..."
curl -X POST -H "Content-Type: application/json" \
  -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  -d @ntfy-contact-point.json \
  "http://localhost:3000/api/alertmanager/grafana/config/api/v1/receivers"

curl -X POST -H "Content-Type: application/json" \
  -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  -d @ntfy-critical-contact-point.json \
  "http://localhost:3000/api/alertmanager/grafana/config/api/v1/receivers"

# Set up notification routing to make ntfy the default
echo "Setting up notification routing..."
cat > notification-policy.json << EOF
{
  "receiver": "ntfy-alerts",
  "group_by": ["alertname", "job"],
  "routes": [
    {
      "receiver": "ntfy-critical-alerts",
      "group_by": ["alertname", "job"],
      "matchers": ["severity=critical"],
      "group_wait": "30s",
      "group_interval": "5m",
      "repeat_interval": "1h"
    }
  ],
  "group_wait": "30s",
  "group_interval": "5m",
  "repeat_interval": "4h"
}
EOF

curl -X PUT -H "Content-Type: application/json" \
  -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  -d @notification-policy.json \
  "http://localhost:3000/api/alertmanager/grafana/config/api/v1/route"

# Create a test alert to verify the setup
echo "Creating a test alert..."
cat > test-alert.json << EOF
{
  "name": "Test Alert",
  "type": "test-alert",
  "settings": {
    "annotations": {
      "summary": "Test notification from Grafana",
      "description": "This is a test notification to verify ntfy integration"
    },
    "labels": {
      "severity": "info"
    }
  }
}
EOF

curl -X POST -H "Content-Type: application/json" \
  -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  -d @test-alert.json \
  "http://localhost:3000/api/alerting/test"

# Cleanup temporary files
rm ntfy-contact-point.json ntfy-critical-contact-point.json notification-policy.json test-alert.json

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "ntfy integration complete."
echo ""
echo "To test the integration, you can:"
echo "1. Subscribe to the '$MONITORING_TOPIC' topic in the ntfy app or web interface (https://notify.gray-beard.com/$MONITORING_TOPIC)"
echo "2. Subscribe to the '$CRITICAL_TOPIC' topic for critical alerts"
echo "3. Create a test alert in Grafana and verify that notifications are sent to ntfy"
echo ""
echo "The following ntfy topics have been set up:"
echo "  - Regular alerts: https://notify.gray-beard.com/$MONITORING_TOPIC"
echo "  - Critical alerts: https://notify.gray-beard.com/$CRITICAL_TOPIC" 