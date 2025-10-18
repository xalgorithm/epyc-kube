#!/bin/bash

# Verify PostgreSQL Initialization Scripts
# This script verifies that the PostgreSQL init scripts are syntactically correct

set -euo pipefail

NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Verifying PostgreSQL Initialization Scripts..."

# Function to extract and test shell scripts from ConfigMap
test_shell_script() {
    local script_name=$1
    local temp_file="/tmp/${script_name}"
    
    echo "Testing $script_name..."
    
    # Extract the script from the ConfigMap
    kubectl get configmap postgresql-config -n "$NAMESPACE" -o jsonpath="{.data['$script_name']}" > "$temp_file"
    
    # Make it executable
    chmod +x "$temp_file"
    
    # Test syntax
    if bash -n "$temp_file"; then
        echo "✅ $script_name syntax is valid"
    else
        echo "❌ $script_name has syntax errors"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_file"
}

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

# Check if ConfigMap exists
if ! kubectl get configmap postgresql-config -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ PostgreSQL ConfigMap does not exist. Please deploy it first."
    exit 1
fi

echo ""
echo "🔍 Testing Shell Script Syntax..."

# Test init scripts
test_shell_script "init-primary.sh"
test_shell_script "init-standby.sh"
test_shell_script "archive_wal.sh"

echo ""
echo "🔍 Checking ConfigMap Content..."

# Show the problematic sections
echo "Checking init-primary.sh here-document:"
kubectl get configmap postgresql-config -n "$NAMESPACE" -o jsonpath="{.data['init-primary.sh']}" | grep -A 5 -B 2 "EOSQL" || echo "No EOSQL found"

echo ""
echo "Checking init-standby.sh here-documents:"
kubectl get configmap postgresql-config -n "$NAMESPACE" -o jsonpath="{.data['init-standby.sh']}" | grep -A 3 -B 1 "EOF" || echo "No EOF found"

echo ""
echo "🔍 Checking PostgreSQL Pod Status..."

# Check if pods are running
PRIMARY_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgresql,component=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
STANDBY_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgresql,component=standby -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$PRIMARY_POD" ]]; then
    echo "Primary pod: $PRIMARY_POD"
    kubectl get pod "$PRIMARY_POD" -n "$NAMESPACE"
    
    echo "Checking primary pod logs for init script errors..."
    if kubectl logs "$PRIMARY_POD" -n "$NAMESPACE" | grep -i "syntax error\|unexpected end of file\|here-document"; then
        echo "⚠️  Found syntax errors in primary pod logs"
    else
        echo "✅ No syntax errors found in primary pod logs"
    fi
else
    echo "⚠️  No primary pod found"
fi

if [[ -n "$STANDBY_POD" ]]; then
    echo ""
    echo "Standby pod: $STANDBY_POD"
    kubectl get pod "$STANDBY_POD" -n "$NAMESPACE"
    
    echo "Checking standby pod logs for init script errors..."
    if kubectl logs "$STANDBY_POD" -n "$NAMESPACE" | grep -i "syntax error\|unexpected end of file\|here-document"; then
        echo "⚠️  Found syntax errors in standby pod logs"
    else
        echo "✅ No syntax errors found in standby pod logs"
    fi
else
    echo "⚠️  No standby pod found"
fi

echo ""
echo "✅ PostgreSQL initialization script verification completed!"

echo ""
echo "📋 Next Steps:"
echo "1. If syntax errors were found, run: ./fix-postgresql-init-scripts.sh"
echo "2. Monitor pod logs: kubectl logs -f -n $NAMESPACE -l app=postgresql"
echo "3. Test database connectivity: kubectl exec -n $NAMESPACE -it $PRIMARY_POD -- psql -U postgres -d airflow -c '\\l'"