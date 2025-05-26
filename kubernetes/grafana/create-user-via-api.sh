#!/bin/bash

set -e

echo "Creating user 'xalg' via Grafana API..."

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

echo "Using admin credentials to create new user..."

# Create the user using Grafana API
curl -X POST -H "Content-Type: application/json" -d '{
  "name": "xalg",
  "email": "xalg@example.com",
  "login": "xalg",
  "password": "admin123.",
  "OrgId": 1,
  "role": "Admin"
}' "http://$ADMIN_USER:$ADMIN_PASSWORD@localhost:3000/api/admin/users"

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "User 'xalg' should now be created with the following credentials:"
echo "Username: xalg"
echo "Password: admin123."
echo ""
echo "Try logging in to https://grafana.gray-beard.com with these credentials." 