# Grafana-Ntfy Integration

This document explains how to use and test the Grafana-Ntfy integration that has been set up in your Kubernetes cluster.

## Overview

The integration allows Grafana to send alert notifications to your Ntfy service. When a Grafana alert fires or resolves, a notification will be sent to the configured Ntfy topic (`grafana-alerts`).

Two integration methods have been set up:

1. **Proxy-based integration**: Uses a small proxy service to transform Grafana's webhook format to Ntfy's format
2. **Direct integration**: Uses Grafana's webhook template functionality to format messages for Ntfy

## Accessing Grafana

You can access Grafana at https://grafana.gray-beard.com using the following credentials:
- Username: `grafana_admin`
- Password: `changeme123`

Note: The original admin account was locked due to too many incorrect login attempts. We've created a new admin user to bypass this limitation.

## Verifying the Integration

To verify that the integration is working properly:

1. Log in to Grafana
2. Go to Alerting > Contact points
3. You should see two contact points:
   - `ntfy-alerts` - Using the proxy integration
   - `ntfy-direct` - Using the direct integration
4. Go to Alerting > Notification policies
5. Verify that the routes are configured correctly

## Testing the Integration

A test alert rule has been deployed that will always fire after 1 minute. This will automatically trigger notifications to your Ntfy service.

You can also test the integration manually:

1. Go to Alerting > Contact points
2. Click on the "Test" button next to either of the Ntfy contact points
3. Fill in the test form and click "Send test notification"
4. You should receive a notification in the Ntfy app or web interface at the `grafana-alerts` topic

## Integration Details

### Proxy-based Integration

- The proxy runs as a deployment in the `monitoring` namespace
- It listens on port 8080 and transforms Grafana's webhook format to Ntfy's format
- It adds appropriate headers and formatting to make alerts more readable

### Direct Integration

- Uses Grafana's webhook templating to format messages directly for Ntfy
- Sends alerts with proper formatting, priorities, and tags
- No additional services required

## Alert Format

Alerts are formatted to include:
- Alert name as the title
- Priority based on alert status (high for firing, default for resolved)
- Tags indicating the status and source
- Detailed message with alert description

## Troubleshooting

If you're not receiving notifications:

1. Check if the proxy pod is running:
   ```
   kubectl get pods -n monitoring -l app=grafana-ntfy-proxy
   ```

2. Check the proxy logs:
   ```
   kubectl logs -n monitoring -l app=grafana-ntfy-proxy
   ```

3. Verify the Ntfy service is working by sending a test message:
   ```
   curl -d "Test message" https://notify.gray-beard.com/grafana-alerts
   ```

4. Check Grafana's alerting logs in the Grafana UI under Alerting > Recent notifications

## Customizing the Integration

You can customize the integration by editing the following files:

- `grafana-integration.yaml` - Proxy-based integration configuration
- `direct-grafana-integration.yaml` - Direct integration configuration
- `grafana-ntfy-proxy.yaml` - Proxy service configuration 