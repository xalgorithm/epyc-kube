#!/bin/bash
set -e

echo "Cleaning up temporary and redundant files..."

# Files to remove
CLEANUP_FILES=(
  # Grafana fix files (merged into grafana-complete-fix.yaml)
  "grafana-datasource-fix.yaml"
  "grafana-provisioning-fix.yaml"
  
  # Redundant/backup files
  "current-grafana-config.yaml"
  "current-prometheus-values.yaml"
  "grafana-auth-values.yaml"
  "grafana-patch.yaml"
  "loki-current-config.yaml"
  "loki-patch.yaml"
  
  # Redundant tf state backups
  "old-terraform.tfstate.backup"
)

# Confirm with the user
echo "The following files will be removed:"
for FILE in "${CLEANUP_FILES[@]}"; do
  if [ -f "$FILE" ]; then
    echo "  - $FILE"
  fi
done

echo
read -p "Are you sure you want to remove these files? (y/n): " CONFIRM

if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
  # Remove the files
  for FILE in "${CLEANUP_FILES[@]}"; do
    if [ -f "$FILE" ]; then
      rm "$FILE"
      echo "Removed: $FILE"
    fi
  done
  echo "Cleanup completed."
else
  echo "Cleanup cancelled."
fi 