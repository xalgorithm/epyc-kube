#!/bin/bash

set -e

echo "Checking Grafana folders and dashboards..."

# Get the Grafana pod name
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

echo "Accessing Grafana database directly to check folders and dashboards..."
kubectl exec -n monitoring $GRAFANA_POD -c grafana -- /bin/bash -c "
  sqlite3 -header -column /var/lib/grafana/grafana.db 'SELECT * FROM dashboard;'
  echo '---------------------------------------'
  echo 'Checking folders:'
  sqlite3 -header -column /var/lib/grafana/grafana.db 'SELECT * FROM dashboard_provisioning;'
  echo '---------------------------------------'
  echo 'Checking dashboard versions:'
  sqlite3 -header -column /var/lib/grafana/grafana.db 'SELECT id, dashboard_id, created, message FROM dashboard_version ORDER BY dashboard_id;'
"

echo "Check complete. You can now manually delete any unnecessary dashboards via the Grafana web UI." 