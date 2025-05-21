# Monitoring in k3s Clusters

## K3s Architecture Differences

K3s is a lightweight Kubernetes distribution that embeds several components differently than standard Kubernetes:

1. **kube-proxy** - K3s uses klipper-lb instead of kube-proxy
2. **kube-controller-manager** - Embedded within the k3s server binary
3. **kube-scheduler** - Embedded within the k3s server binary

These architectural differences cause false alerts when using standard Kubernetes monitoring configurations, such as those from kube-prometheus-stack.

## Alert Suppression

The file `prometheus-rule-suppress.yaml` contains rules to inhibit false alerts related to these components. This uses the "InfoInhibitor" pattern to prevent alerts from firing unnecessarily.

## ServiceMonitor Cleanup

For a more permanent solution, the script `k3s-cleanup-servicemonitors.sh` removes the ServiceMonitors that are targeting these components. This stops Prometheus from attempting to scrape metrics endpoints that don't exist in k3s.

## Common Alerts for K3s

If you are receiving these alerts, they are normal for k3s clusters:

- KubeProxyDown
- KubeControllerManagerDown
- KubeSchedulerDown

## Usage

1. Apply the suppression rule:
   ```
   kubectl apply -f kubernetes/prometheus-rule-suppress.yaml
   ```

2. If you want to remove the ServiceMonitors completely:
   ```
   ./kubernetes/k3s-cleanup-servicemonitors.sh
   ```

## Restoring Default Configuration

If you migrate to a standard Kubernetes cluster in the future, you'll need to restore these ServiceMonitors by reinstalling the kube-prometheus-stack. 