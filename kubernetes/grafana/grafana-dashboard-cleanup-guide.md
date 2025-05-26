# Grafana Dashboard Cleanup Guide

Since you're now able to log in to Grafana, here's a guide to manually clean up dashboards that don't have data:

## Steps to Clean Up Dashboards

1. Log in to Grafana at https://grafana.gray-beard.com using your credentials.

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

## Alternative Method

If you prefer to delete dashboards directly from the command line, you can try this after setting up port forwarding:

```bash
# Set up port forwarding
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Then in another terminal:
# List all dashboards
curl -s -u "admin:admin" http://localhost:3000/api/search?type=dash-db | jq

# Delete a specific dashboard (replace DASHBOARD_UID with the actual UID)
curl -X DELETE -u "admin:admin" http://localhost:3000/api/dashboards/uid/DASHBOARD_UID
```

## Best Practices

- Don't delete system dashboards that are part of your monitoring stack
- Focus on removing custom dashboards that are no longer in use
- Consider organizing dashboards into folders for better management
- Tag dashboards to help with organization and identification

Remember that some dashboards might appear empty if the data source is temporarily unavailable, so check the data source status before deleting. 