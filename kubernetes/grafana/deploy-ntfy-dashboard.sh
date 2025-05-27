#!/bin/bash

set -e

echo "Deploying ntfy service and dashboard..."

# Deploy ntfy service
echo "Deploying ntfy service..."
kubectl apply -f ntfy-deployment.yaml

# Wait for the deployment to be ready
echo "Waiting for ntfy deployment to be ready..."
kubectl rollout status deployment/ntfy -n monitoring

# Wait a bit for the metrics to start collecting
echo "Waiting for metrics to start collecting..."
sleep 30

# Import the dashboard
echo "Importing the ntfy dashboard..."
./import-ntfy-dashboard.sh

echo "ntfy service and dashboard deployment complete."
echo "You can access ntfy at: https://notify.gray-beard.com"
echo "You can access the dashboard at the Grafana URL under the ntfy dashboard." 