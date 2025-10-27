#!/bin/bash
set -e

echo "Organizing project files..."

# Create necessary directories if they don't exist
mkdir -p kubernetes/grafana
mkdir -p kubernetes/prometheus
mkdir -p kubernetes/loki

# Files to move to kubernetes/grafana/
GRAFANA_FILES=(
  "grafana-complete-fix.yaml"
  "grafana-admin-credentials.yaml"
)

# Files to move to kubernetes/prometheus/
PROMETHEUS_FILES=(
  "combined-prometheus-values.yaml"
  "kube-prometheus-values.yaml"
)

# Files to move to kubernetes/loki/
LOKI_FILES=(
  "loki-datasource-patch.yaml"
  "loki-ruler-config.yaml"
  "loki-datasource.yaml"
)

# Function to move files
move_files() {
  local files=("$@")
  local dest_dir="${files[0]}"
  
  # Remove the first element (dest_dir)
  files=("${files[@]:1}")
  
  for file in "${files[@]}"; do
    if [ -f "$file" ]; then
      echo "Moving $file to $dest_dir/"
      mv "$file" "$dest_dir/"
    else
      echo "File not found: $file"
    fi
  done
}

# Move Grafana files
echo "Moving Grafana files..."
move_files "kubernetes/grafana" "${GRAFANA_FILES[@]}"

# Move Prometheus files
echo "Moving Prometheus files..."
move_files "kubernetes/prometheus" "${PROMETHEUS_FILES[@]}"

# Move Loki files
echo "Moving Loki files..."
move_files "kubernetes/loki" "${LOKI_FILES[@]}"

# Handle grafana-backup directory
if [ -d "grafana-backup" ]; then
  echo "Moving grafana-backup contents to kubernetes/grafana/backup/"
  mkdir -p kubernetes/grafana/backup
  
  # List files in grafana-backup
  backup_files=$(ls -A grafana-backup)
  
  if [ -n "$backup_files" ]; then
    mv grafana-backup/* kubernetes/grafana/backup/
    rmdir grafana-backup
    echo "Moved grafana-backup contents and removed the directory"
  else
    echo "grafana-backup directory is empty"
  fi
fi

echo "File organization completed!" 