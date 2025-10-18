#!/bin/bash

# Test Airflow Monitoring Configuration
# This script tests Prometheus metrics collection for Airflow
# Requirements: 3.1, 3.7 - Verify metrics collection

set -euo pipefail

NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Testing Airflow Monitoring Configuration..."

# Function to check if a pod is ready
check_pod_ready() {
    local deployment=$1
    local timeout=${2:-300}
    
    echo "Checking if $deployment is ready..."
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "✅ $deployment is ready"
        return 0
    else
        echo "❌ $deployment is not ready"
        return 1
    fi
}

# Function to test metrics endpoint
test_metrics_endpoint() {
    local service=$1
    local port=$2
    local path=${3:-/metrics}
    
    echo "Testing metrics endpoint: $service:$port$path"
    
    # Port forward and test
    kubectl port-forward -n "$NAMESPACE" service/$service $port:$port >/dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait a moment for port forward to establish
    sleep 3
    
    # Test the endpoint
    if curl -s --max-time 10 "http://localhost:$port$path" | head -5 | grep -q "^#"; then
        echo "✅ Metrics endpoint $service:$port$path is responding"
        kill $pf_pid 2>/dev/null || true
        return 0
    else
        echo "❌ Metrics endpoint $service:$port$path is not responding"
        kill $pf_pid 2>/dev/null || true
        return 1
    fi
}

# Function to check ServiceMonitor
check_servicemonitor() {
    local name=$1
    
    echo "Checking ServiceMonitor: $name"
    if kubectl get servicemonitor "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "✅ ServiceMonitor $name exists"
        return 0
    else
        echo "❌ ServiceMonitor $name does not exist"
        return 1
    fi
}

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist"
    exit 1
fi

echo ""
echo "🔍 Checking Monitoring Components..."

# Check deployments
DEPLOYMENTS=("airflow-statsd-exporter" "postgresql-exporter" "redis-exporter")
for deployment in "${DEPLOYMENTS[@]}"; do
    check_pod_ready "$deployment" 60
done

echo ""
echo "🔍 Checking ServiceMonitors..."

# Check ServiceMonitors
SERVICEMONITORS=("airflow-statsd-exporter" "airflow-webserver" "airflow-scheduler" "airflow-workers" "airflow-flower" "postgresql-exporter" "redis-metrics")
for sm in "${SERVICEMONITORS[@]}"; do
    check_servicemonitor "$sm"
done

echo ""
echo "🔍 Testing Metrics Endpoints..."

# Test metrics endpoints
echo "Testing StatsD Exporter..."
test_metrics_endpoint "airflow-statsd-exporter" "9102"

echo "Testing PostgreSQL Exporter..."
test_metrics_endpoint "postgresql-exporter" "9187"

echo "Testing Redis Exporter..."
test_metrics_endpoint "redis-metrics" "9121"

echo ""
echo "🔍 Checking Pod Logs for Errors..."

# Check logs for errors
echo "Checking StatsD Exporter logs..."
if kubectl logs -n "$NAMESPACE" deployment/airflow-statsd-exporter --tail=10 | grep -i error; then
    echo "⚠️  Found errors in StatsD Exporter logs"
else
    echo "✅ No errors in StatsD Exporter logs"
fi

echo "Checking PostgreSQL Exporter logs..."
if kubectl logs -n "$NAMESPACE" deployment/postgresql-exporter --tail=10 | grep -i error; then
    echo "⚠️  Found errors in PostgreSQL Exporter logs"
else
    echo "✅ No errors in PostgreSQL Exporter logs"
fi

echo "Checking Redis Exporter logs..."
if kubectl logs -n "$NAMESPACE" deployment/redis-exporter --tail=10 | grep -i error; then
    echo "⚠️  Found errors in Redis Exporter logs"
else
    echo "✅ No errors in Redis Exporter logs"
fi

echo ""
echo "🔍 Checking Prometheus Discovery..."

# Check if Prometheus can discover the ServiceMonitors
echo "Checking if Prometheus operator is running..."
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus >/dev/null 2>&1; then
    echo "✅ Prometheus operator is running"
    
    # Get Prometheus pod
    PROM_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$PROM_POD" ]]; then
        echo "Checking Prometheus targets..."
        kubectl port-forward -n monitoring pod/$PROM_POD 9090:9090 >/dev/null 2>&1 &
        local prom_pf_pid=$!
        
        sleep 3
        
        # Check if targets are discovered
        if curl -s --max-time 10 "http://localhost:9090/api/v1/targets" | jq -r '.data.activeTargets[] | select(.labels.namespace=="airflow") | .labels.job' 2>/dev/null | grep -q "airflow"; then
            echo "✅ Airflow targets discovered by Prometheus"
        else
            echo "⚠️  Airflow targets may not be discovered by Prometheus yet"
        fi
        
        kill $prom_pf_pid 2>/dev/null || true
    fi
else
    echo "⚠️  Prometheus operator not found in monitoring namespace"
fi

echo ""
echo "📊 Sample Metrics Check..."

# Show sample metrics from each exporter
echo "Sample StatsD metrics:"
kubectl port-forward -n "$NAMESPACE" service/airflow-statsd-exporter 9102:9102 >/dev/null 2>&1 &
local statsd_pf_pid=$!
sleep 2
curl -s --max-time 5 "http://localhost:9102/metrics" | grep "^airflow_" | head -3 || echo "No Airflow metrics found yet"
kill $statsd_pf_pid 2>/dev/null || true

echo ""
echo "Sample PostgreSQL metrics:"
kubectl port-forward -n "$NAMESPACE" service/postgresql-exporter 9187:9187 >/dev/null 2>&1 &
local pg_pf_pid=$!
sleep 2
curl -s --max-time 5 "http://localhost:9187/metrics" | grep "^pg_" | head -3 || echo "No PostgreSQL metrics found"
kill $pg_pf_pid 2>/dev/null || true

echo ""
echo "Sample Redis metrics:"
kubectl port-forward -n "$NAMESPACE" service/redis-metrics 9121:9121 >/dev/null 2>&1 &
local redis_pf_pid=$!
sleep 2
curl -s --max-time 5 "http://localhost:9121/metrics" | grep "^redis_" | head -3 || echo "No Redis metrics found"
kill $redis_pf_pid 2>/dev/null || true

echo ""
echo "✅ Monitoring configuration test completed!"

echo ""
echo "📋 Next Steps:"
echo "1. Redeploy Airflow with updated values to enable StatsD metrics"
echo "2. Verify metrics are flowing in Prometheus UI"
echo "3. Create Grafana dashboards for visualization"
echo "4. Set up alerting rules based on these metrics"

echo ""
echo "🔗 Useful Commands:"
echo "kubectl get servicemonitors -n $NAMESPACE"
echo "kubectl get pods -n $NAMESPACE -l tier=monitoring"
echo "kubectl port-forward -n $NAMESPACE service/airflow-statsd-exporter 9102:9102"
echo "kubectl port-forward -n $NAMESPACE service/postgresql-exporter 9187:9187"
echo "kubectl port-forward -n $NAMESPACE service/redis-metrics 9121:9121"