#!/bin/bash

set -e

echo "Testing Grafana login from inside the cluster..."

# Create a temporary pod to test the login
kubectl run curl-test --image=curlimages/curl:8.3.0 -n monitoring --rm -it --restart=Never -- \
  curl -s -v "http://kube-prometheus-stack-grafana.monitoring/api/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"xalg","password":"admin123."}'

echo "If you see a 'Redirecting to /...' response, the login is working."
echo "If you're still having issues logging in via the browser, it might be related to cookies, cache, or browser settings."
echo "Try clearing your browser cache, using incognito mode, or using a different browser." 