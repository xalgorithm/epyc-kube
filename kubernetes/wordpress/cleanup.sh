#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."  # Go to project root

echo "Cleaning up old WordPress configuration files..."

# Files that were deleted or moved to kubernetes/wordpress directory
OLD_WP_FILES=(
  "wordpress-ingress.yaml"
  "wordpress-ingress-latest.yaml"
  "https-redirect.yaml"
  "wordpress-ingress-current.yaml"
  "letsencrypt-prod-issuer.yaml"
  "wordpress-ingress-new.yaml"
  "wordpress-backup.yaml"
  "wordpress-deployment.yaml"
  "fix-permissions-job.yaml"
)

# Check if any of these files still exist
FILES_FOUND=0
for FILE in "${OLD_WP_FILES[@]}"; do
  if [ -f "$FILE" ]; then
    if [ $FILES_FOUND -eq 0 ]; then
      echo "Found the following old WordPress files:"
      FILES_FOUND=1
    fi
    echo "  - $FILE"
  fi
done

if [ $FILES_FOUND -eq 0 ]; then
  echo "No old WordPress files found. Cleanup already completed."
  exit 0
fi

echo
read -p "Are you sure you want to remove these files? (y/n): " CONFIRM

if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
  # Remove the files
  for FILE in "${OLD_WP_FILES[@]}"; do
    if [ -f "$FILE" ]; then
      rm "$FILE"
      echo "Removed: $FILE"
    fi
  done
  echo "WordPress cleanup completed."
else
  echo "WordPress cleanup cancelled."
fi 