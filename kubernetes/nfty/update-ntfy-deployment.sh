#!/bin/bash

# Script to update the ntfy deployment after removing public access
# This applies the changes made to make ntfy private and only accessible via port-forwarding

set -e

echo "Updating ntfy deployment to remove public access..."

# Apply the updated deployment
kubectl apply -f ../grafana/ntfy-deployment.yaml

# Restart the deployment to ensure changes take effect
kubectl rollout restart deployment/ntfy -n monitoring

# Wait for rollout to complete
echo "Waiting for deployment to stabilize..."
kubectl rollout status deployment/ntfy -n monitoring

echo "Ntfy has been updated to be accessible only via port-forwarding."
echo "To connect to ntfy, run: ./connect-to-ntfy.sh"
echo ""
echo "For more information, see README-secure-access.md" 