#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Updating Alertmanager configuration with email notifications..."

# Check if the alertmanager secret exists
if kubectl -n monitoring get secret alertmanager-kube-prometheus-stack-alertmanager > /dev/null 2>&1; then
  # Apply the configuration directly (password is already in the file)
  kubectl apply -f alertmanager-config.yaml
  
  # Restart the Alertmanager pod to apply changes
  kubectl -n monitoring rollout restart statefulset alertmanager-kube-prometheus-stack-alertmanager
  
  echo "Alertmanager configuration updated successfully."
  echo "Wait for Alertmanager to restart..."
  kubectl -n monitoring rollout status statefulset alertmanager-kube-prometheus-stack-alertmanager
  
  echo "Email notifications have been configured with contact@example.com as the sender"
  echo "You will receive alerts at admin@example.com"
else
  echo "Error: Alertmanager secret not found. Make sure kube-prometheus-stack is installed correctly."
  exit 1
fi 