#!/bin/bash

# Copy MetalLB Firewall Script to Proxmox Host
# Helper script to transfer the firewall configuration script

set -euo pipefail

PROXMOX_HOST="${1:-}"
SCRIPT_PATH="scripts/configure-proxmox-firewall-for-metallb.sh"

if [ -z "$PROXMOX_HOST" ]; then
    echo "Usage: $0 root@proxmox-host-ip"
    echo ""
    echo "This script will:"
    echo "1. Copy the firewall configuration script to Proxmox host"
    echo "2. Make it executable"
    echo "3. Provide execution instructions"
    exit 1
fi

echo "🚀 Copying MetalLB Firewall Script to Proxmox Host"
echo "=================================================="
echo ""
echo "📊 Target: $PROXMOX_HOST"
echo "📁 Script: $SCRIPT_PATH"
echo ""

# Copy the script
echo "📋 Copying script..."
scp "$SCRIPT_PATH" "$PROXMOX_HOST:/tmp/configure-proxmox-firewall-for-metallb.sh"

# Make it executable
echo "📋 Making script executable..."
ssh "$PROXMOX_HOST" "chmod +x /tmp/configure-proxmox-firewall-for-metallb.sh"

echo ""
echo "✅ Script copied successfully!"
echo ""
echo "🔧 To execute on Proxmox host:"
echo "ssh $PROXMOX_HOST"
echo "/tmp/configure-proxmox-firewall-for-metallb.sh"
echo ""
echo "📊 The script will:"
echo "• Check current firewall rules"
echo "• Add HTTP/HTTPS rules for MetalLB subnet"
echo "• Save rules permanently"
echo "• Test connectivity"
echo ""
echo "⏳ Background monitoring will detect when HTTP access works"
