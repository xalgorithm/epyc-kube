# Grafana Configuration Backup

This directory contains exported configurations for your customized Grafana setup in Kubernetes.

## Files

- `grafana-deployment-export.yaml`: Current Grafana deployment configuration
- `grafana-credentials-export.yaml`: The Kubernetes secret containing Grafana credentials
- `grafana-datasources-export.yaml`: ConfigMap with Grafana datasource configurations
- `helm-values-export.yaml`: Current Helm chart values for kube-prometheus-stack
- `grafana-upgrade-values.yaml`: Simplified values file for future Helm upgrades

## Credentials

Grafana is configured with custom credentials:
- Username: `xalg`
- Password: Stored in the `grafana-admin-credentials` secret

## Upgrading Grafana

To upgrade Grafana while preserving your custom credentials and settings, use:

```bash
# Apply the secret first if it doesn't exist
kubectl apply -f grafana-backup/grafana-credentials-export.yaml

# Upgrade using your simplified values file
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f grafana-backup/grafana-upgrade-values.yaml
```

## Complete Restoration

In case you need to completely restore the current setup:

```bash
# Apply the credentials secret
kubectl apply -f grafana-backup/grafana-credentials-export.yaml

# Apply the datasources ConfigMap
kubectl apply -f grafana-backup/grafana-datasources-export.yaml

# Apply the deployment directly if Helm upgrade fails
kubectl apply -f grafana-backup/grafana-deployment-export.yaml
```

## Note

When using the simplified values file (`grafana-upgrade-values.yaml`), Helm will manage most resources while still using your custom credentials from the Kubernetes secret. 