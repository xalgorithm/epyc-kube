#!/bin/bash

set -e

echo "Testing admin login from inside the cluster..."

# Create a temporary pod to test the login
kubectl run curl-test --image=curlimages/curl:8.3.0 -n monitoring --rm -it --restart=Never -- \
  curl -s -v "http://kube-prometheus-stack-grafana.monitoring/api/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","password":"admin"}'

echo "If you see a successful response, the login credentials are working."
echo "Try logging in to https://grafana.gray-beard.com with username 'admin' and password 'admin'."
echo "If you're still having issues, try clearing your browser cache and cookies, or use incognito/private mode." 