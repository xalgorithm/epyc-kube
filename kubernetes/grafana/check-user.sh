#!/bin/bash

set -e

echo "Checking if user 'xalg' exists in Grafana..."

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

echo "Checking users in Grafana..."

# List all users using Grafana API
curl -s "http://$ADMIN_USER:$ADMIN_PASSWORD@localhost:3000/api/users" | jq .

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "User check complete. If you don't see the xalg user, there might be an issue with the user creation or authentication configuration." 