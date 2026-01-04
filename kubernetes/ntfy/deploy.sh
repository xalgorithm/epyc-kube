#!/bin/bash

set -e

# Create the namespace first
kubectl apply -f namespace.yaml

# Apply Kubernetes resources
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress-tls.yaml

echo "Ntfy deployment completed!"
echo "Access your ntfy instance at: https://notify.gray-beard.com"
echo "iOS push notifications should now work correctly with the NTFY_UPSTREAM_BASE_URL set to ntfy.sh" 