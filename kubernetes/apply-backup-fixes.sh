#!/bin/bash

# Apply Backup System Fixes
# This script fixes the persistent backup failures

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Backup System Fix Application                         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "error" ]; then
        echo -e "${RED}✗${NC} $message"
    elif [ "$status" = "info" ]; then
        echo -e "${BLUE}ℹ${NC} $message"
    elif [ "$status" = "warning" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    fi
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_status "error" "kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if backup namespace exists
if ! kubectl get namespace backup &> /dev/null; then
    print_status "error" "Backup namespace does not exist. Creating it..."
    kubectl create namespace backup
    print_status "success" "Created backup namespace"
fi

# Verify the fixes file exists
if [ ! -f "backup-fixes.yaml" ]; then
    print_status "error" "backup-fixes.yaml not found in current directory"
    exit 1
fi

print_status "info" "Analyzing current backup system state..."
echo

# Show current failing pods
echo -e "${YELLOW}Current failing backup pods:${NC}"
kubectl get pods -n backup --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null || echo "  None found"
echo

# Show current CronJobs
echo -e "${YELLOW}Current backup CronJobs:${NC}"
kubectl get cronjobs -n backup 2>/dev/null || echo "  None found"
echo

# Confirm before proceeding
read -p "$(echo -e ${YELLOW}Do you want to proceed with applying the fixes? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "info" "Operation cancelled by user"
    exit 0
fi

echo
print_status "info" "Step 1: Deleting existing failed backup jobs..."
kubectl delete jobs -n backup --field-selector=status.successful!=1 2>/dev/null || true
print_status "success" "Cleaned up failed jobs"
echo

print_status "info" "Step 2: Creating backup storage PVC..."
# Extract and apply only the PVC first
kubectl apply -f backup-fixes.yaml --selector='!batch.kubernetes.io/job-name' 2>&1 | grep -E "(persistentvolumeclaim|created|configured)" || true
sleep 5

# Wait for PVC to be bound
print_status "info" "Waiting for PVC to be bound..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    pvc_status=$(kubectl get pvc -n backup backup-storage-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$pvc_status" = "Bound" ]; then
        print_status "success" "PVC is bound and ready"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo -n "."
done
echo

if [ "$pvc_status" != "Bound" ]; then
    print_status "warning" "PVC is not bound yet (status: $pvc_status), but continuing..."
fi

print_status "info" "Step 3: Updating CronJobs with fixes..."
kubectl apply -f backup-fixes.yaml
print_status "success" "Applied all backup fixes"
echo

print_status "info" "Step 4: Verifying the fixes..."
echo

# Check PVC status
echo -e "${YELLOW}Backup Storage PVC Status:${NC}"
kubectl get pvc -n backup backup-storage-pvc -o wide 2>/dev/null || print_status "error" "PVC not found"
echo

# Check CronJob status
echo -e "${YELLOW}Updated CronJobs:${NC}"
kubectl get cronjobs -n backup -o wide
echo

# Check if any pods are still failing
echo -e "${YELLOW}Current pod status:${NC}"
kubectl get pods -n backup 2>/dev/null || echo "  No pods currently running"
echo

# Show node labels for verification
echo -e "${YELLOW}Control plane node labels (for etcd-backup):${NC}"
kubectl get nodes -l node-role.kubernetes.io/control-plane=true -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels 2>/dev/null || \
    print_status "warning" "No nodes found with control-plane=true label"
echo

print_status "success" "Backup system fixes applied successfully!"
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Next Steps:${NC}"
echo -e "  1. Monitor the backup jobs: ${YELLOW}kubectl get pods -n backup -w${NC}"
echo -e "  2. Check CronJob schedules: ${YELLOW}kubectl get cronjobs -n backup${NC}"
echo -e "  3. View backup logs: ${YELLOW}kubectl logs -n backup <pod-name>${NC}"
echo -e "  4. Verify PVC usage: ${YELLOW}kubectl get pvc -n backup${NC}"
echo
echo -e "${BLUE}Troubleshooting:${NC}"
echo -e "  - If PVC is not binding, check NFS provisioner: ${YELLOW}kubectl get pods -n nfs-provisioner${NC}"
echo -e "  - If etcd-backup still fails, verify node labels: ${YELLOW}kubectl get nodes --show-labels${NC}"
echo -e "  - Check events: ${YELLOW}kubectl get events -n backup --sort-by='.lastTimestamp'${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

