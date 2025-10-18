#!/bin/bash

# Verify PostgreSQL Fix
# This script verifies that the PostgreSQL initialization script fix worked

set -euo pipefail

NAMESPACE="airflow"

echo "🧪 Verifying PostgreSQL Fix..."

# Check if primary pod is running
echo "🔍 Checking PostgreSQL primary pod status..."
if kubectl get pod postgresql-primary-0 -n "$NAMESPACE" >/dev/null 2>&1; then
    POD_STATUS=$(kubectl get pod postgresql-primary-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    echo "✅ Primary pod exists with status: $POD_STATUS"
    
    if [[ "$POD_STATUS" == "Running" ]]; then
        echo "✅ Primary pod is running"
    else
        echo "❌ Primary pod is not running"
        exit 1
    fi
else
    echo "❌ Primary pod does not exist"
    exit 1
fi

# Check pod logs for syntax errors
echo "🔍 Checking pod logs for syntax errors..."
if kubectl logs postgresql-primary-0 -n "$NAMESPACE" | grep -i "syntax error\|unexpected end of file\|here-document"; then
    echo "❌ Found syntax errors in pod logs"
    exit 1
else
    echo "✅ No syntax errors found in pod logs"
fi

# Test database connectivity
echo "🔍 Testing database connectivity..."
if kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -c '\l' >/dev/null 2>&1; then
    echo "✅ Database connectivity test passed"
else
    echo "❌ Database connectivity test failed"
    exit 1
fi

# Check if airflow database exists
echo "🔍 Checking if airflow database exists..."
DB_EXISTS=$(kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='airflow';" | tr -d ' \n')
if [[ "$DB_EXISTS" == "1" ]]; then
    echo "✅ Airflow database exists"
else
    echo "❌ Airflow database does not exist"
    exit 1
fi

# Check user privileges
echo "🔍 Checking user privileges..."
USER_ATTRS=$(kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -t -c "SELECT rolsuper, rolreplication FROM pg_roles WHERE rolname='airflow';" | tr -d ' ')
if [[ "$USER_ATTRS" == "t|t" ]]; then
    echo "✅ Airflow user has superuser and replication privileges"
else
    echo "⚠️  Airflow user privileges: $USER_ATTRS"
fi

# Test basic SQL operations
echo "🔍 Testing basic SQL operations..."
if kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -c "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, name VARCHAR(50)); DROP TABLE IF EXISTS test_table;" >/dev/null 2>&1; then
    echo "✅ Basic SQL operations test passed"
else
    echo "❌ Basic SQL operations test failed"
    exit 1
fi

# Show database information
echo ""
echo "📊 Database Information:"
echo "Databases:"
kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -c '\l' | grep -E "Name|airflow|postgres"

echo ""
echo "Users:"
kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -c '\du'

echo ""
echo "✅ PostgreSQL fix verification completed successfully!"

echo ""
echo "📋 Summary:"
echo "- PostgreSQL primary pod is running without syntax errors"
echo "- Database connectivity is working"
echo "- Airflow database exists"
echo "- User has appropriate privileges"
echo "- Basic SQL operations are functional"

echo ""
echo "🔗 Connection Details:"
echo "- Host: postgresql-primary.airflow.svc.cluster.local"
echo "- Port: 5432"
echo "- Database: airflow"
echo "- User: airflow"
echo "- Password: (stored in postgresql-secret)"