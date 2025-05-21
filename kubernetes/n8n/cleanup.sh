#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Cleaning up unused n8n files..."

# Files currently used in deployment (from deploy.sh)
USED_FILES=(
  "namespace.yaml"
  "pvc.yaml"
  "secret.yaml"
  "deployment.yaml"
  "service.yaml"
  "ingress-tls.yaml"
  "servicemonitor.yaml"
  "alertrule.yaml"
  "grafana-dashboard-cm.yaml"
  "deploy.sh"
)

# Also keep this cleanup script
USED_FILES+=("cleanup.sh")

# Files to be removed
FILES_TO_REMOVE=(
  "n8n-secret.yaml.sample"
  "n8n-secret-updated.yaml"
  "n8n-deployment.yaml"
  "n8n-backup-job.yaml"
  "n8n-backup-cronjob.yaml"
  "n8n-backup-pvc.yaml"
  "n8n-backup-script.yaml"
  "n8n-deployment-updated.yaml"
  "n8n-ingress-tls.yaml"
  "n8n-namespace.yaml"
)

# Confirm with the user
echo "The following files will be removed:"
for FILE in "${FILES_TO_REMOVE[@]}"; do
  if [ -f "$FILE" ]; then
    echo "  - $FILE"
  fi
done

echo
read -p "Are you sure you want to remove these files? (y/n): " CONFIRM

if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
  # Remove the files
  for FILE in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$FILE" ]; then
      rm "$FILE"
      echo "Removed: $FILE"
    fi
  done
  echo "Cleanup completed."
else
  echo "Cleanup cancelled."
fi 