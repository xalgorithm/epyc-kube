#!/bin/bash

# Create backup directory if it doesn't exist
mkdir -p ../grafana/backup

# Move Grafana-related files to the grafana folder
mv grafana-admin-reset.yaml ../grafana/
mv reset-grafana-admin.sh ../grafana/
mv grafana-new-admin.yaml ../grafana/
mv create-new-admin.sh ../grafana/
mv reset-grafana.sh ../grafana/
mv grafana-ntfy-integration.md ../grafana/
mv grafana-integration.yaml ../grafana/
mv direct-grafana-integration.yaml ../grafana/
mv grafana-ntfy-proxy.yaml ../grafana/
mv deploy-grafana-integration.sh ../grafana/
mv test-alert-rule.yaml ../grafana/

echo "Grafana files have been moved to the ../grafana/ directory" 