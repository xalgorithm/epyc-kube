#!/bin/bash

set -e

echo "Cleaning up dashboards in Grafana that don't have data..."

# Get the Grafana pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

# Create a port-forward to the Grafana pod
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring $GRAFANA_POD 3000:3000 &
PORT_FORWARD_PID=$!

# Wait for port-forward to establish
sleep 5

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASSWORD="admin"
AUTH_HEADER="Authorization: Basic $(echo -n ${ADMIN_USER}:${ADMIN_PASSWORD} | base64)"

echo "Fetching all dashboards..."
DASHBOARDS=$(curl -s -H "$AUTH_HEADER" "http://localhost:3000/api/search?type=dash-db")

# Check if we got any dashboards
if [[ $(echo "$DASHBOARDS" | grep -c "messageId") -gt 0 ]]; then
  echo "Error fetching dashboards. Authentication may have failed."
  echo "Response: $DASHBOARDS"
  kill $PORT_FORWARD_PID
  exit 1
fi

# Extract dashboard UIDs
DASHBOARD_UIDS=$(echo "$DASHBOARDS" | jq -r '.[].uid')

if [[ -z "$DASHBOARD_UIDS" ]]; then
  echo "No dashboards found."
  kill $PORT_FORWARD_PID
  exit 0
fi

echo "Found dashboards: $DASHBOARD_UIDS"

# Process each dashboard
for UID in $DASHBOARD_UIDS; do
  echo "Checking dashboard $UID..."
  
  # Get the dashboard details
  DASHBOARD=$(curl -s -H "$AUTH_HEADER" "http://localhost:3000/api/dashboards/uid/$UID")
  
  # Get dashboard title
  TITLE=$(echo "$DASHBOARD" | jq -r '.dashboard.title')
  echo "Dashboard title: $TITLE"
  
  # Check if it has panels
  PANELS_COUNT=$(echo "$DASHBOARD" | jq '.dashboard.panels | length')
  
  # Check if panels have datasources
  HAS_DATASOURCE=false
  if [[ "$PANELS_COUNT" -gt 0 ]]; then
    DATASOURCES=$(echo "$DASHBOARD" | jq -r '.dashboard.panels[].datasource')
    if [[ ! -z "$DATASOURCES" && "$DATASOURCES" != "null" ]]; then
      HAS_DATASOURCE=true
    fi
  fi
  
  if [[ "$PANELS_COUNT" -eq 0 || "$HAS_DATASOURCE" == "false" ]]; then
    echo "Dashboard $TITLE ($UID) appears to be empty or without data sources. Deleting..."
    DELETE_RESULT=$(curl -X DELETE -H "$AUTH_HEADER" "http://localhost:3000/api/dashboards/uid/$UID")
    echo "Delete result: $DELETE_RESULT"
  else
    echo "Dashboard $TITLE ($UID) has $PANELS_COUNT panels with data sources. Keeping it."
  fi
done

# Kill the port-forward process
kill $PORT_FORWARD_PID

echo "Dashboard cleanup complete." 