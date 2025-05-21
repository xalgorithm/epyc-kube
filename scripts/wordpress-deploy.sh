#!/bin/bash
set -e

# Configuration
WORDPRESS_NAMESPACE="wordpress"
WORDPRESS_POD=$(kubectl get pods -n $WORDPRESS_NAMESPACE -l app=wordpress -o jsonpath="{.items[0].metadata.name}")
LOCAL_REPO_PATH="$(pwd)/wordpress-site"
REMOTE_PATH="/var/www/html"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="/tmp/wordpress-k8s-backup-${TIMESTAMP}"
TEMP_TAR="/tmp/wordpress-deploy-${TIMESTAMP}.tar.gz"

# Check that the local repository exists
if [ ! -d "${LOCAL_REPO_PATH}" ]; then
  echo "Error: Local WordPress repository not found at ${LOCAL_REPO_PATH}"
  echo "Run the wordpress-sync.sh script first to create it."
  exit 1
fi

# Prompt for confirmation
echo "WARNING: This will deploy local WordPress files to the live Kubernetes pod."
echo "Make sure you have tested your changes locally before proceeding."
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 0
fi

# Create backup of current files in the pod
echo "Creating backup of current WordPress files in pod..."
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- mkdir -p ${BACKUP_DIR}
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "tar --warning=no-file-changed -czf ${BACKUP_DIR}/wordpress-backup.tar.gz -C ${REMOTE_PATH} ."

# Optional: Download backup locally
read -p "Download pod backup locally? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  mkdir -p "${LOCAL_REPO_PATH}/.backups"
  echo "Downloading backup locally..."
  kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:${BACKUP_DIR}/wordpress-backup.tar.gz "${LOCAL_REPO_PATH}/.backups/pod-backup-${TIMESTAMP}.tar.gz" -c wordpress
  echo "Backup saved to ${LOCAL_REPO_PATH}/.backups/pod-backup-${TIMESTAMP}.tar.gz"
fi

# Check for wp-config.php in local repository
if [ ! -f "${LOCAL_REPO_PATH}/wp-config.php" ]; then
  echo "Warning: wp-config.php not found in local repository."
  echo "This is expected if it's excluded from git."
  echo "The existing wp-config.php in the pod will be preserved."
  
  # Create temporary directory for deployment without wp-config.php
  echo "Creating temporary archive for deployment..."
  TEMP_DIR=$(mktemp -d)
  
  # Copy local repo to temp dir
  cp -r "${LOCAL_REPO_PATH}"/* "${TEMP_DIR}/"
  
  # Get wp-config.php from pod and add to temp dir
  echo "Retrieving wp-config.php from pod..."
  kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:${REMOTE_PATH}/wp-config.php "${TEMP_DIR}/wp-config.php" -c wordpress
  
  # Create tar archive
  echo "Creating deployment archive..."
  tar -czf ${TEMP_TAR} -C "${TEMP_DIR}" .
  
  # Clean up temp dir
  rm -rf "${TEMP_DIR}"
else
  # Create tar archive directly from local repo
  echo "Creating deployment archive..."
  tar -czf ${TEMP_TAR} -C "${LOCAL_REPO_PATH}" .
fi

# Copy archive to pod
echo "Copying deployment archive to pod..."
kubectl cp -n ${WORDPRESS_NAMESPACE} ${TEMP_TAR} ${WORDPRESS_POD}:/tmp/wordpress-deploy.tar.gz -c wordpress

# Extract archive in pod
echo "Extracting files in pod..."
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "tar --warning=no-file-changed -xzf /tmp/wordpress-deploy.tar.gz -C ${REMOTE_PATH}"

# Fix permissions in the pod
echo "Fixing permissions in the pod..."
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- chown -R www-data:www-data ${REMOTE_PATH}
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- chmod -R 755 ${REMOTE_PATH}
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- chmod -R 775 ${REMOTE_PATH}/wp-content

# Clean up
echo "Cleaning up temporary files..."
rm -f ${TEMP_TAR}
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- rm -f /tmp/wordpress-deploy.tar.gz

echo "WordPress deployment complete!"
echo "If you need to restore from backup, you can use:"
echo "kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- tar -xzf ${BACKUP_DIR}/wordpress-backup.tar.gz -C ${REMOTE_PATH}" 