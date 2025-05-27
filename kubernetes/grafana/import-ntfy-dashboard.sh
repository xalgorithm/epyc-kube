#!/bin/bash

set -e

echo "Importing ntfy monitoring dashboard to Grafana..."

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
sleep 5

# Prepare the dashboard data
echo "Preparing dashboard data..."
cat > dashboard-import.json << EOF
{
  "dashboard": $(cat ntfy-dashboard.json),
  "overwrite": true,
  "folderId": 0
}
EOF

# Import the dashboard
echo "Importing ntfy dashboard..."
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -u "$ADMIN_USER:$ADMIN_PASSWORD" \
  -d @dashboard-import.json \
  "http://localhost:3000/api/dashboards/db" \
  -v

# Clean up temporary file
rm dashboard-import.json

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "ntfy dashboard import complete."
echo "You can access the dashboard at:"
echo "http://grafana.your-domain.com/d/ntfy-monitoring/ntfy-monitoring-dashboard" 