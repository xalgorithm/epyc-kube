#!/bin/bash

set -e

echo "WARNING: This will completely reset Grafana and all its data."
echo "Are you sure you want to continue? (y/n)"
read -r response

if [[ "$response" != "y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "Performing a complete reset of Grafana..."

# Scale down Grafana
kubectl scale deployment -n monitoring kube-prometheus-stack-grafana --replicas=0
echo "Waiting for Grafana to scale down..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=60s

# Find and delete the PVC used by Grafana
GRAFANA_PVC=$(kubectl get pvc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
if [ -n "$GRAFANA_PVC" ]; then
    echo "Deleting Grafana PVC: $GRAFANA_PVC"
    kubectl delete pvc -n monitoring "$GRAFANA_PVC"
else
    echo "No Grafana PVC found."
fi

# Create a new ConfigMap with admin credentials
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-reset-config
  namespace: monitoring
data:
  grafana.ini: |
    [security]
    admin_user = admin
    admin_password = changeme123
    disable_initial_admin_creation = false
    [auth]
    login_maximum_inactive_lifetime_duration = 7d
    login_maximum_lifetime_duration = 30d
    disable_login_form = false
    [auth.basic]
    enabled = true
    [users]
    allow_sign_up = false
    auto_assign_org = true
    auto_assign_org_role = Admin
EOF

# Update the Grafana deployment to use our ConfigMap
kubectl patch deployment -n monitoring kube-prometheus-stack-grafana --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "grafana",
          "volumeMounts": [{
            "mountPath": "/etc/grafana/grafana.ini",
            "name": "reset-config",
            "subPath": "grafana.ini"
          }]
        }],
        "volumes": [{
          "name": "reset-config",
          "configMap": {
            "name": "grafana-reset-config"
          }
        }]
      }
    }
  }
}'

# Scale up Grafana
kubectl scale deployment -n monitoring kube-prometheus-stack-grafana --replicas=1
echo "Waiting for Grafana to start up..."
kubectl wait --for=condition=available deployment -n monitoring kube-prometheus-stack-grafana --timeout=120s

echo "Grafana has been reset with the following credentials:"
echo "Username: admin"
echo "Password: changeme123"
echo ""
echo "Try logging in to https://grafana.gray-beard.com with these credentials."
echo ""
echo "Note: Since Grafana has been reset, you'll need to reconfigure any dashboards or alerting rules that were previously set up." 