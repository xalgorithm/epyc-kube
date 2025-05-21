#!/bin/bash
set -e

echo "Removing irrelevant ServiceMonitors for k3s clusters..."

# Delete the ServiceMonitors that don't apply to k3s
kubectl delete servicemonitor kube-prometheus-stack-kube-proxy -n monitoring
kubectl delete servicemonitor kube-prometheus-stack-kube-controller-manager -n monitoring
kubectl delete servicemonitor kube-prometheus-stack-kube-scheduler -n monitoring

# Delete the test alert we created
kubectl delete -f kubernetes/test-alert.yaml

echo "The irrelevant ServiceMonitors have been removed."
echo "Note: This is normal for k3s clusters as these components are embedded in k3s"
echo "and not exposed as separate services with their own metrics endpoints."
echo ""
echo "The alerts KubeProxyDown, KubeControllerManagerDown, and KubeSchedulerDown should stop firing." 