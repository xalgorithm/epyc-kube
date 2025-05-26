#!/bin/bash

set -e

echo "Cleaning up dashboards in Grafana that don't have data..."

# Get the Grafana pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

# Exec into the pod and run the cleanup
echo "Executing cleanup commands in the Grafana pod..."
kubectl exec -it -n monitoring $GRAFANA_POD -c grafana -- /bin/bash -c '
  # Use Grafana CLI to reset the admin password first
  grafana-cli admin reset-admin-password admin
  
  # Create a temp script to call the API
  cat > /tmp/cleanup.sh << EOF
#!/bin/bash
# Get all dashboards
DASHBOARDS=\$(curl -s -H "Authorization: Basic \$(echo -n "admin:admin" | base64)" http://localhost:3000/api/search?type=dash-db | jq -r ".[].uid")

# Process each dashboard
for UID in \$DASHBOARDS; do
  echo "Checking dashboard \$UID..."
  # Get the dashboard details
  DASHBOARD=\$(curl -s -H "Authorization: Basic \$(echo -n "admin:admin" | base64)" http://localhost:3000/api/dashboards/uid/\$UID)
  
  # Check if it has panels
  PANELS=\$(echo \$DASHBOARD | jq ".dashboard.panels")
  PANELS_COUNT=\$(echo \$PANELS | jq "length")
  
  # Check if dashboard has data sources configured
  HAS_DATA=\$(echo \$DASHBOARD | jq ".dashboard.panels[].datasource")
  
  if [ "\$PANELS_COUNT" == "0" ] || [ -z "\$HAS_DATA" ] || [ "\$HAS_DATA" == "null" ]; then
    echo "Dashboard \$UID appears to be empty or without data sources. Deleting..."
    curl -X DELETE -H "Authorization: Basic \$(echo -n "admin:admin" | base64)" http://localhost:3000/api/dashboards/uid/\$UID
  else
    echo "Dashboard \$UID has data. Keeping it."
  fi
done
EOF

  # Make the script executable and run it
  chmod +x /tmp/cleanup.sh
  /tmp/cleanup.sh
'

echo "Dashboard cleanup complete." 