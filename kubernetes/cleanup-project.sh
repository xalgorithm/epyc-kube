#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."  # Go to project root

echo "Cleaning up unused files in the project..."

# Files to remove
UNUSED_FILES=(
  # Backup files
  "main.tf.bak"

  # Redundant Grafana ingress/config files
  "kubernetes/grafana/grafana-ingress.yaml"      # Using grafana-ingress-tls.yaml
  "kubernetes/grafana/grafana-ingress-k8s.yaml"  # Not used, we're using the TLS version
  "kubernetes/grafana/grafana-config-simple.yaml"  # Superseded by config-update
  "kubernetes/grafana/grafana-config-patch.yaml"   # Superseded by config-update

  # Redundant Traefik files
  "kubernetes/traefik/traefik-deployment-patch.yaml"  # Not using this approach

  # Test files
  "kubernetes/test-alert.yaml"  # Just for testing, no longer needed
  
  # Duplicate/old scripts
  "kubernetes/disable-kubeproxy-servicemonitor.sh"  # Replaced by k3s-cleanup-servicemonitors.sh
)

# Confirm with the user
echo "The following files will be removed:"
for FILE in "${UNUSED_FILES[@]}"; do
  if [ -f "$FILE" ]; then
    echo "  - $FILE"
  fi
done

echo
read -p "Are you sure you want to remove these files? (y/n): " CONFIRM

if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
  # Remove the files
  for FILE in "${UNUSED_FILES[@]}"; do
    if [ -f "$FILE" ]; then
      rm "$FILE"
      echo "Removed: $FILE"
    fi
  done
  echo "Cleanup completed."
else
  echo "Cleanup cancelled."
fi 