# ntfy Integration for Grafana Monitoring Stack

This document explains how to use the ntfy integration with your Grafana monitoring stack. The integration allows Grafana to send alert notifications to your mobile devices or desktop through the ntfy service.

## Overview

[ntfy](https://notify.gray-beard.com/docs/) is a simple push notification service that allows sending notifications to your phone or desktop via HTTP requests. The integration configured in this repository makes ntfy the default notification channel for your Grafana monitoring stack.

## Getting Started

### Prerequisites

- Kubernetes cluster with Grafana deployed
- Access to the ntfy service at https://notify.gray-beard.com

### Deployment

1. Run the deployment script:
   ```bash
   cd kubernetes/grafana
   chmod +x deploy-ntfy-integration.sh
   ./deploy-ntfy-integration.sh
   ```

2. Subscribe to ntfy topics:
   - Install the ntfy app on your mobile device from [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy) or [F-Droid](https://f-droid.org/packages/io.heckel.ntfy/)
   - Subscribe to the following topics:
     - `monitoring-alerts`: For regular monitoring alerts
     - `critical-alerts`: For high-priority alerts

3. Test the integration:
   ```bash
   curl -d "Test alert from monitoring system" https://notify.gray-beard.com/monitoring-alerts
   ```

## How It Works

### Notification Types

The integration configures two types of notification channels:

1. **Regular Alerts** (`monitoring-alerts`):
   - Used for normal monitoring alerts
   - Displayed with standard priority on your devices

2. **Critical Alerts** (`critical-alerts`):
   - Used for high-severity alerts
   - Displayed with urgent priority, which can trigger more intrusive notifications
   - Tagged with `warning,critical,alert` for better visibility

### Alert Formatting

Alerts are formatted with:

- **Title**: The alert name or "Multiple Alerts" for multiple alerts
- **Message**: Contains the number of alerts, their names, and summary information
- **Tags**: Automatically added based on alert status (firing vs resolved)
- **Priority**: Set based on severity (urgent for critical, high for others)

### Integration Components

The integration consists of:

1. **ConfigMaps**:
   - `grafana-ntfy-integration`: Basic ntfy contact point configuration
   - `grafana-ntfy-templates`: Advanced message templates for ntfy
   - `grafana-ntfy-provisioning`: Grafana notification channel provisioning

2. **Scripts**:
   - `grafana-ntfy-integration.sh`: Sets up the ntfy contact points and routes in Grafana
   - `deploy-ntfy-integration.sh`: Deploys all components and applies configurations

## Customization

### Custom Topics

To use custom topic names:

1. Edit `grafana-ntfy-integration.sh` and change the `MONITORING_TOPIC` and `CRITICAL_TOPIC` variables
2. Update the topic URLs in `grafana-ntfy-provisioning` ConfigMap
3. Rerun the deployment script

### Message Templates

To customize message formatting:

1. Edit the templates in `grafana-ntfy-templates.yaml`
2. Reapply the ConfigMap with `kubectl apply -f grafana-ntfy-templates.yaml`
3. Restart Grafana with `kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana`

## Troubleshooting

### No Notifications

If you're not receiving notifications:

1. Check that you're subscribed to the correct topics
2. Test direct notification with curl:
   ```bash
   curl -d "Test message" https://notify.gray-beard.com/monitoring-alerts
   ```
3. Check Grafana's alerting logs in the Grafana UI under Alerting > Recent notifications
4. Verify that the ntfy contact points are properly configured in Grafana

### Incorrect Alert Formatting

If alert formatting is incorrect:

1. Check the templates in `grafana-ntfy-templates.yaml`
2. Verify that the templates are correctly mounted in the Grafana pod
3. Inspect the Grafana logs for any template rendering errors

## References

- [ntfy Documentation](https://notify.gray-beard.com/docs/)
- [Grafana Alerting Documentation](https://grafana.com/docs/grafana/latest/alerting/)
- [ntfy GitHub Repository](https://github.com/binwiederhier/ntfy) 