#!/bin/bash

# Script to diagnose and fix NFS connectivity issues
# This script will help identify why Kubernetes nodes can't connect to the NFS server

set -e

KUBECONFIG_FILE="kubeconfig.yaml"
NFS_SERVER="10.0.1.210"
NFS_PATH="/data"

echo "🔍 Diagnosing NFS connectivity issues..."
echo "========================================"
echo "NFS Server: $NFS_SERVER"
echo "NFS Path: $NFS_PATH"
echo ""

# Function to test from a Kubernetes node
test_from_k8s_node() {
    local node=$1
    local node_ip=$2
    
    echo "🔍 Testing from Kubernetes node: $node ($node_ip)"
    echo "------------------------------------------------"
    
    echo "1. Testing basic connectivity:"
    if ssh -F ssh_config $node "timeout 5 ping -c 1 $NFS_SERVER" >/dev/null 2>&1; then
        echo "   ✅ Ping successful"
    else
        echo "   ❌ Ping failed"
    fi
    
    echo "2. Testing NFS port (2049):"
    if ssh -F ssh_config $node "timeout 5 nc -z $NFS_SERVER 2049" >/dev/null 2>&1; then
        echo "   ✅ NFS port accessible"
    else
        echo "   ❌ NFS port not accessible"
    fi
    
    echo "3. Testing RPC port (111):"
    if ssh -F ssh_config $node "timeout 5 nc -z $NFS_SERVER 111" >/dev/null 2>&1; then
        echo "   ✅ RPC port accessible"
    else
        echo "   ❌ RPC port not accessible"
    fi
    
    echo "4. Testing NFS mount capability:"
    ssh -F ssh_config $node "
        sudo mkdir -p /tmp/nfs-test
        if timeout 10 sudo mount -t nfs $NFS_SERVER:$NFS_PATH /tmp/nfs-test 2>/dev/null; then
            echo '   ✅ NFS mount successful'
            sudo umount /tmp/nfs-test
        else
            echo '   ❌ NFS mount failed'
        fi
        sudo rmdir /tmp/nfs-test 2>/dev/null || true
    "
    
    echo ""
}

# Test from all Kubernetes nodes
test_from_k8s_node "gimli" "10.0.1.211"
test_from_k8s_node "legolas" "10.0.1.212"
test_from_k8s_node "aragorn" "10.0.1.213"

echo "🔧 Potential fixes to try:"
echo "=========================="
echo ""
echo "If the NFS server is accessible but NFS ports are blocked:"
echo "1. On the NFS server ($NFS_SERVER), check if NFS services are running:"
echo "   sudo systemctl status nfs-server"
echo "   sudo systemctl status rpcbind"
echo ""
echo "2. Check firewall rules on the NFS server:"
echo "   sudo ufw status"
echo "   sudo iptables -L"
echo ""
echo "3. Ensure NFS ports are open on the NFS server:"
echo "   sudo ufw allow from 10.0.1.0/24 to any port nfs"
echo "   sudo ufw allow from 10.0.1.0/24 to any port 111"
echo ""
echo "4. Check NFS exports on the server:"
echo "   sudo exportfs -v"
echo ""
echo "5. Restart NFS services on the server:"
echo "   sudo systemctl restart nfs-server"
echo "   sudo systemctl restart rpcbind"
echo ""

# Check current NFS provisioner status
echo "📊 Current NFS provisioner status:"
echo "=================================="
kubectl --kubeconfig=$KUBECONFIG_FILE get pods -n nfs-provisioner 2>/dev/null || echo "No NFS provisioner pods found"
echo ""

# Check failed mounts
echo "🚨 Pods with NFS mount failures:"
echo "================================"
kubectl --kubeconfig=$KUBECONFIG_FILE get events --all-namespaces --field-selector reason=FailedMount | grep -i nfs | tail -10

echo ""
echo "💡 Quick fix options:"
echo "===================="
echo ""
echo "Option 1: Fix NFS connectivity (recommended if you want to keep your data)"
echo "   - Follow the diagnostic steps above"
echo "   - Ensure NFS server is properly configured and accessible"
echo ""
echo "Option 2: Restart NFS provisioner after fixing connectivity"
echo "   kubectl --kubeconfig=$KUBECONFIG_FILE rollout restart deployment -n nfs-provisioner nfs-subdir-external-provisioner"
echo ""
echo "Option 3: Temporarily use local storage (data loss)"
echo "   - Run the migration script to move to local storage"
echo "   - This will lose all existing data but get services running quickly"