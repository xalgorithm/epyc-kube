#!/bin/bash
set -e

# Configuration
WORDPRESS_NAMESPACE="wordpress"
WORDPRESS_POD=$(kubectl get pods -n $WORDPRESS_NAMESPACE -l app=wordpress -o jsonpath="{.items[0].metadata.name}")
LOCAL_REPO_PATH="$(pwd)/wordpress-site"
REMOTE_PATH="/var/www/html"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="${LOCAL_REPO_PATH}/.backups"
TEMP_DIR="/tmp/wordpress-temp-${TIMESTAMP}"

# Error handling
handle_error() {
  echo "Error: $1"
  rm -rf "${TEMP_DIR}"
  exit 1
}

# Create directories if they don't exist
mkdir -p "${LOCAL_REPO_PATH}"
mkdir -p "${BACKUP_DIR}"
mkdir -p "${TEMP_DIR}"

# Initialize git repo if it doesn't exist
if [ ! -d "${LOCAL_REPO_PATH}/.git" ]; then
  echo "Initializing git repository in ${LOCAL_REPO_PATH}"
  cd "${LOCAL_REPO_PATH}"
  git init
  echo "wp-config.php" > .gitignore
  echo ".backups/" >> .gitignore
  echo "*.log" >> .gitignore
  echo "wp-content/cache/" >> .gitignore
  echo "wp-content/upgrade/" >> .gitignore
  echo "wp-content/uploads/backup-*/" >> .gitignore
  git add .gitignore
  git commit -m "Initial commit: Add .gitignore"
  cd - > /dev/null
fi

# Backup existing local git repository if needed
if [ -d "${LOCAL_REPO_PATH}/.git" ] && [ "$(ls -A ${LOCAL_REPO_PATH})" != "" ]; then
  echo "Creating backup of current git repository state..."
  cd "${LOCAL_REPO_PATH}"
  git add -A
  git stash save "Backup before sync - ${TIMESTAMP}" || true
  cd - > /dev/null
fi

# Clear the existing files to avoid conflicts (preserve .git directory)
find "${LOCAL_REPO_PATH}" -mindepth 1 -not -path "${LOCAL_REPO_PATH}/.git*" -not -path "${LOCAL_REPO_PATH}/.backups*" -delete

# List major WordPress directories (excluding wp-content which we'll handle separately)
DIRS_TO_SYNC=(
  "wp-admin"
  "wp-includes"
)

# Copy WordPress files from the pod incrementally
echo "Copying WordPress files from pod ${WORDPRESS_POD}..."

# First copy individual files in the root directory
echo "Copying files in root directory..."
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- find ${REMOTE_PATH} -maxdepth 1 -type f -name "*.php" > "${TEMP_DIR}/root_files.txt"
while IFS= read -r file; do
  filename=$(basename "$file")
  echo "Copying $filename..."
  kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:"$file" "${LOCAL_REPO_PATH}/$filename" -c wordpress || echo "Warning: Failed to copy $filename"
done < "${TEMP_DIR}/root_files.txt"

# Copy main directories (wp-admin, wp-includes)
for dir in "${DIRS_TO_SYNC[@]}"; do
  echo "Copying directory $dir..."
  kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "[ -d ${REMOTE_PATH}/$dir ]" || continue
  
  # Create directory locally
  mkdir -p "${LOCAL_REPO_PATH}/$dir"
  
  # Create a temporary tar file for this directory
  kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "cd ${REMOTE_PATH} && tar --warning=no-file-changed -czf /tmp/$dir.tar.gz $dir" || handle_error "Failed to create archive for $dir"
  
  # Copy and extract the directory
  kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:/tmp/$dir.tar.gz "${TEMP_DIR}/$dir.tar.gz" -c wordpress || handle_error "Failed to copy archive for $dir"
  tar -xzf "${TEMP_DIR}/$dir.tar.gz" -C "${LOCAL_REPO_PATH}" || handle_error "Failed to extract $dir"
  
  # Clean up
  kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- rm -f /tmp/$dir.tar.gz
done

# Handle wp-content directory separately by subdirectories
echo "Creating wp-content directory structure..."
mkdir -p "${LOCAL_REPO_PATH}/wp-content"

# Get wp-content subdirectories
echo "Getting wp-content subdirectories..."
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- find ${REMOTE_PATH}/wp-content -maxdepth 1 -type d -not -path "${REMOTE_PATH}/wp-content" > "${TEMP_DIR}/wp_content_dirs.txt"

# Copy each wp-content subdirectory individually
while IFS= read -r subdir; do
  subdir_name=$(basename "$subdir")
  echo "Copying wp-content/$subdir_name..."
  
  # Create the subdirectory locally
  mkdir -p "${LOCAL_REPO_PATH}/wp-content/$subdir_name"
  
  # Try to create a tar file for this subdirectory (but don't fail if it's empty)
  kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "cd ${REMOTE_PATH}/wp-content && tar --warning=no-file-changed -czf /tmp/$subdir_name.tar.gz $subdir_name" || echo "Warning: Failed to create archive for $subdir_name (might be empty)"
  
  # Copy and extract if the archive was created successfully
  if kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "[ -f /tmp/$subdir_name.tar.gz ]"; then
    kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:/tmp/$subdir_name.tar.gz "${TEMP_DIR}/$subdir_name.tar.gz" -c wordpress || echo "Warning: Failed to copy archive for $subdir_name"
    if [ -f "${TEMP_DIR}/$subdir_name.tar.gz" ]; then
      tar -xzf "${TEMP_DIR}/$subdir_name.tar.gz" -C "${LOCAL_REPO_PATH}/wp-content" || echo "Warning: Failed to extract $subdir_name"
    fi
  fi
  
  # Clean up
  kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- rm -f /tmp/$subdir_name.tar.gz || true
done < "${TEMP_DIR}/wp_content_dirs.txt"

# Also copy files directly in wp-content
echo "Copying files in wp-content root..."
kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- find ${REMOTE_PATH}/wp-content -maxdepth 1 -type f > "${TEMP_DIR}/wp_content_files.txt"
while IFS= read -r file; do
  filename=$(basename "$file")
  echo "Copying wp-content/$filename..."
  kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:"$file" "${LOCAL_REPO_PATH}/wp-content/$filename" -c wordpress || echo "Warning: Failed to copy $filename"
done < "${TEMP_DIR}/wp_content_files.txt"

# Clean up temporary files
rm -rf "${TEMP_DIR}"

# Get wp-config.php but don't commit it
if kubectl exec -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD} -c wordpress -- bash -c "[ -f ${REMOTE_PATH}/wp-config.php ]"; then
  echo "Retrieving wp-config.php (not for git)..."
  kubectl cp -n ${WORDPRESS_NAMESPACE} ${WORDPRESS_POD}:${REMOTE_PATH}/wp-config.php "${BACKUP_DIR}/wp-config-${TIMESTAMP}.php" -c wordpress
  
  # Create a sanitized version for git tracking
  if [ -f "${BACKUP_DIR}/wp-config-${TIMESTAMP}.php" ]; then
    sed 's/define(.*DB_PASSWORD.*/define( '\''DB_PASSWORD'\'', '\''**REDACTED**'\'' );/g' "${BACKUP_DIR}/wp-config-${TIMESTAMP}.php" > "${LOCAL_REPO_PATH}/wp-config-example.php"
  fi
fi

# Commit changes
cd "${LOCAL_REPO_PATH}"
echo "Committing changes to local git repository..."
git add .
git commit -m "Sync WordPress files from Kubernetes pod - ${TIMESTAMP}" || echo "No changes to commit"

echo "WordPress synchronization complete!"
echo "WordPress files synced to: ${LOCAL_REPO_PATH}"
echo ""
echo "Next steps:"
echo "1. Review changes: cd ${LOCAL_REPO_PATH} && git status"
echo "2. Push to GitHub: cd ${LOCAL_REPO_PATH} && git remote add origin YOUR_GITHUB_REPO_URL && git push -u origin main"
echo "3. Schedule this script to run periodically with cron if desired" 