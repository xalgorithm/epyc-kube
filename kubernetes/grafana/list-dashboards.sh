#!/bin/bash

set -e

echo "Listing all dashboards in Grafana..."

# Get the Grafana pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

# Create a port-forward to the Grafana pod
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring $GRAFANA_POD 3000:3000 &
PORT_FORWARD_PID=$!

# Wait for port-forward to establish
sleep 5

# Hard-code the admin credentials we set up
ADMIN_USER="admin"
ADMIN_PASSWORD="admin"

echo "Fetching dashboards..."

# List all dashboards using Grafana API
curl -s "http://$ADMIN_USER:$ADMIN_PASSWORD@localhost:3000/api/search?type=dash-db" | jq .

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "Dashboard listing complete." 