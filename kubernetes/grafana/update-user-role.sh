#!/bin/bash

set -e

echo "Updating 'xalg' user role to Admin in Grafana..."

# Get the Grafana pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

# Create a port-forward to the Grafana pod
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring $GRAFANA_POD 3000:3000 &
PORT_FORWARD_PID=$!

# Wait for port-forward to establish
sleep 5

# Get admin password
ADMIN_PASSWORD=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
ADMIN_USER=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-user}" | base64 --decode)

echo "Making user xalg an admin..."

# Update the user to have admin privileges
curl -X PUT -H "Content-Type: application/json" -d '{
  "isGrafanaAdmin": true
}' "http://$ADMIN_USER:$ADMIN_PASSWORD@localhost:3000/api/admin/users/2/permissions"

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "User 'xalg' should now have admin privileges."
echo "Try logging in to https://grafana.gray-beard.com with the following credentials:"
echo "Username: xalg"
echo "Password: admin123." 