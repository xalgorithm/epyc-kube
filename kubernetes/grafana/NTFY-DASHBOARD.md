# ntfy Dashboard for Grafana

This directory contains files for setting up a comprehensive ntfy monitoring dashboard in Grafana. The dashboard provides insights into the performance and usage of the ntfy notification service.

## Dashboard Overview

The ntfy dashboard includes the following panels:

1. **Messages Published Rate** - Rate of messages published to different topics
2. **Messages Delivered Rate** - Rate of messages delivered to subscribers
3. **Current Subscribers** - Number of active subscribers
4. **Active Topics** - Count of active topics
5. **Memory Usage** - Server memory usage
6. **CPU Usage** - Server CPU usage
7. **HTTP Request Duration** - 95th percentile of HTTP request durations
8. **HTTP Request Rate by Status Code** - Rate of HTTP requests by status code
9. **Memory Usage Over Time** - Memory usage of the ntfy process over time

## Files

- `ntfy-dashboard.json` - The Grafana dashboard definition
- `import-ntfy-dashboard.sh` - Script to import the dashboard into Grafana
- `ntfy-deployment.yaml` - Kubernetes deployment for the ntfy service
- `deploy-ntfy-dashboard.sh` - Script to deploy the service and dashboard

## Setup Instructions

### Prerequisites

- Kubernetes cluster with Prometheus and Grafana installed
- `kubectl` configured to access your cluster
- Optional: HashiCorp Vault for secure credential management

### Deployment Steps

1. Deploy the ntfy service and dashboard:

```bash
./deploy-ntfy-dashboard.sh
```

This script will:
- Deploy the ntfy service to your cluster
- Wait for the deployment to be ready
- Import the dashboard into Grafana

### Manually Deploying Components

If you prefer to deploy components manually:

1. Deploy the ntfy service:

```bash
kubectl apply -f ntfy-deployment.yaml
```

2. Import the dashboard:

```bash
./import-ntfy-dashboard.sh
```

## Accessing the Dashboard

After deployment:

1. Access the ntfy service at: `https://notify.gray-beard.com`
2. Access the dashboard through your Grafana instance, under the name "ntfy Monitoring Dashboard"

## Dashboard Customization

To customize the dashboard:
1. Import it into Grafana
2. Make your desired changes
3. Save the dashboard
4. Export it and replace the existing `ntfy-dashboard.json` file

## Integration with Alerting

The ntfy service is integrated with Grafana's alerting system through two channels:
- Regular alerts: sent to the `monitoring-alerts` topic
- Critical alerts: sent to the `critical-alerts` topic with high priority

To subscribe to alerts:
1. Visit `https://notify.gray-beard.com/monitoring-alerts` or `https://notify.gray-beard.com/critical-alerts`
2. Use the ntfy app or web interface to subscribe

## Troubleshooting

If metrics are not appearing in the dashboard:
1. Verify the ntfy pod is running: `kubectl get pods -n monitoring`
2. Check the ServiceMonitor is working: `kubectl get servicemonitor -n monitoring`
3. Verify Prometheus is scraping the target: Check the Prometheus targets page in Grafana

## Known Issues

- The dashboard assumes ntfy exposes metrics in Prometheus format
- Some metrics may require the ntfy service to run for a while before they appear 