# Grafana Configuration

This directory contains configuration files and scripts for Grafana, focusing on monitoring and alerting with ntfy integration.

## Main Components

### ntfy Integration

The ntfy integration allows Grafana to send notifications through the ntfy service, which can then be received on mobile devices, desktops, or web browsers.

Key files:
- `grafana-ntfy-integration.sh` - Script to configure ntfy as the default notification mechanism
- `test-ntfy-notification.sh` - Test script to verify ntfy notifications with different formats

### ntfy Dashboard

A comprehensive dashboard for monitoring the ntfy service itself:
- `ntfy-dashboard.json` - Dashboard definition
- `import-ntfy-dashboard.sh` - Script to import the dashboard
- `ntfy-deployment.yaml` - Kubernetes deployment for the ntfy service
- `deploy-ntfy-dashboard.sh` - Script to deploy the service and dashboard
- `test-ntfy-metrics.sh` - Script to generate test data for the dashboard

For detailed information about the ntfy dashboard, see [NTFY-DASHBOARD.md](./NTFY-DASHBOARD.md).

## Quick Start

### Setting Up ntfy Notifications

To set up ntfy as the default notification mechanism for Grafana:

```bash
./grafana-ntfy-integration.sh
```

### Deploying ntfy Dashboard

To deploy the ntfy service and its dashboard:

```bash
./deploy-ntfy-dashboard.sh
```

### Testing

To test ntfy notifications:

```bash
./test-ntfy-notification.sh
```

To generate test data for the dashboard:

```bash
./test-ntfy-metrics.sh
```

## Integration with Other Services

The ntfy integration can be used by other services by sending HTTP requests to the ntfy service:

```bash
curl -H "Title: Alert Title" \
     -H "Priority: high" \
     -H "Tags: warning,system" \
     -d "Alert message details" \
     https://notify.gray-beard.com/topic-name
```

Where `topic-name` is the name of the notification channel you want to use.

## Security Considerations

- The ntfy service is configured to use HTTPS
- Credentials for Grafana are retrieved securely from HashiCorp Vault when available
- For sensitive topics, consider setting up authentication on the ntfy server 