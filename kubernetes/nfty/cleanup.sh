#!/bin/bash

# Script to clean up nfty resources
# Use with caution - this will delete all nfty resources including persistent data

set -e

echo "This will delete all nfty resources including persistent data."
echo "Are you sure you want to continue? (y/n)"
read -r answer

if [[ "$answer" != "y" ]]; then
  echo "Cleanup aborted."
  exit 0
fi

# Delete all resources
kubectl delete -f ingress-tls.yaml --ignore-not-found
kubectl delete -f service.yaml --ignore-not-found
kubectl delete -f deployment.yaml --ignore-not-found
kubectl delete -f pvc.yaml --ignore-not-found

# Wait a moment before deleting the namespace
echo "Waiting for resources to terminate..."
sleep 5

# Delete the namespace last
kubectl delete -f namespace.yaml --ignore-not-found

echo "Nfty resources have been cleaned up." 