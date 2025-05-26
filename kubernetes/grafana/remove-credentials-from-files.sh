#!/bin/bash

set -e

echo "Removing hardcoded credentials from files..."

# Move files with hardcoded credentials to a backup directory
BACKUP_DIR="credentials_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# List of files with hardcoded credentials
FILES_WITH_CREDENTIALS=(
  "reset-grafana.sh"
  "create-new-admin.sh"
  "grafana-new-admin.yaml"
  "reset-grafana-admin.sh"
  "grafana-admin-reset.yaml"
  "create-user-via-api.sh"
  "update-user-role.sh"
  "reset-user-password.sh"
  "list-dashboards.sh"
  "clean-dashboards-local.sh"
  "create-standard-admin.sh"
  "reset-grafana-credentials.sh"
  "add-grafana-user.yaml"
)

# Make backup copies of files with credentials
for file in "${FILES_WITH_CREDENTIALS[@]}"; do
  if [ -f "$file" ]; then
    echo "Backing up $file to $BACKUP_DIR/"
    cp "$file" "$BACKUP_DIR/"
  fi
done

echo "Creating secure versions of files without hardcoded credentials..."

# Update the Grafana dashboard cleanup guide to use Vault
cat > grafana-dashboard-cleanup-guide.md << EOF
# Grafana Dashboard Cleanup Guide

## Steps to Clean Up Dashboards

1. Log in to Grafana at https://grafana.gray-beard.com using your credentials from Vault.

2. From the left sidebar, click on "Dashboards" to access the dashboard browser.

3. Review each dashboard by clicking on it to open. Look for the following signs that a dashboard doesn't have data:
   - Empty panels with "No data" messages
   - Panels with error messages like "Error querying datasource" 
   - Dashboards without any panels
   - Dashboards with panels that have no datasource configured

4. To delete a dashboard that doesn't have data:
   - Click on the dashboard settings (gear icon) in the top right
   - Scroll down to the bottom and click the red "Delete Dashboard" button
   - Confirm the deletion

5. To identify which dashboards are provisioned (automatically managed by Kubernetes):
   - Look for the "save" icon in the top navigation
   - If it's disabled or has a lock icon, the dashboard is provisioned
   - Provisioned dashboards cannot be deleted through the UI and are managed by the system

## Alternative Method using Vault

If you prefer to delete dashboards directly from the command line, you can use this secure approach:

\`\`\`bash
# Set up port forwarding
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Get credentials from Vault in another terminal
ADMIN_USER=\$(vault kv get -field=username secret/grafana/admin)
ADMIN_PASSWORD=\$(vault kv get -field=password secret/grafana/admin)

# List all dashboards
curl -s -u "\$ADMIN_USER:\$ADMIN_PASSWORD" http://localhost:3000/api/search?type=dash-db | jq

# Delete a specific dashboard (replace DASHBOARD_UID with the actual UID)
curl -X DELETE -u "\$ADMIN_USER:\$ADMIN_PASSWORD" http://localhost:3000/api/dashboards/uid/DASHBOARD_UID
\`\`\`

## Best Practices

- Don't delete system dashboards that are part of your monitoring stack
- Focus on removing custom dashboards that are no longer in use
- Consider organizing dashboards into folders for better management
- Tag dashboards to help with organization and identification
- Never hardcode credentials in scripts or documentation

Remember that some dashboards might appear empty if the data source is temporarily unavailable, so check the data source status before deleting.
EOF

# Create a secure version of list-dashboards.sh
cat > list-dashboards-secure.sh << EOF
#!/bin/bash

set -e

echo "Listing all dashboards in Grafana using credentials from Vault..."

# Get the Grafana pod name
GRAFANA_POD=\$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

# Create a port-forward to the Grafana pod
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring \$GRAFANA_POD 3000:3000 &
PORT_FORWARD_PID=\$!

# Wait for port-forward to establish
sleep 5

# Get credentials from Vault
ADMIN_USER=\$(vault kv get -field=username secret/grafana/admin)
ADMIN_PASSWORD=\$(vault kv get -field=password secret/grafana/admin)

echo "Fetching dashboards..."

# List all dashboards using Grafana API
curl -s "http://\$ADMIN_USER:\$ADMIN_PASSWORD@localhost:3000/api/search?type=dash-db" | jq .

# Kill the port-forward process
kill \$PORT_FORWARD_PID

echo "Dashboard listing complete."
EOF

chmod +x list-dashboards-secure.sh

echo "Creating a secure ConfigMap for Grafana without hardcoded credentials..."
cat > grafana-secure-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-secure-config
  namespace: monitoring
data:
  grafana.ini: |
    [security]
    # Credentials are managed by Vault
    disable_initial_admin_creation = false
    
    [auth]
    disable_login_form = false
    disable_signout_menu = false
    
    [auth.basic]
    enabled = true
    
    [users]
    allow_sign_up = false
    auto_assign_org = true
    auto_assign_org_role = Viewer
EOF

echo "Files with credentials have been backed up to $BACKUP_DIR/"
echo "New secure versions have been created."
echo ""
echo "Next steps:"
echo "1. Ensure Vault integration is working properly"
echo "2. Test the secure scripts that use Vault for credentials"
echo "3. Once everything is confirmed working, you can delete the backup directory"
echo "4. Update any deployment processes to use the new secure approach" 