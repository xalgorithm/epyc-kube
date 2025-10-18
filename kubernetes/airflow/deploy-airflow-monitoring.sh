#!/bin/bash

# Deploy Airflow Monitoring Configuration
# This script deploys Prometheus metrics collection for Airflow
# Requirements: 3.1, 3.7 - Configure Prometheus metrics collection

set -euo pipefail

NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Deploying Airflow Monitoring Configuration..."

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

# Check if Prometheus operator is installed
if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo "❌ Prometheus operator is not installed. ServiceMonitor CRD not found."
    echo "Please install kube-prometheus-stack first."
    exit 1
fi

echo "📊 Deploying StatsD Exporter..."
kubectl apply -f "$SCRIPT_DIR/airflow-statsd-exporter.yaml"

echo "📈 Deploying ServiceMonitors..."
kubectl apply -f "$SCRIPT_DIR/airflow-servicemonitors.yaml"

echo "🗄️ Deploying PostgreSQL Exporter..."
kubectl apply -f "$SCRIPT_DIR/postgresql-exporter.yaml"

echo "🔄 Updating Redis Exporter..."
kubectl apply -f "$SCRIPT_DIR/redis-servicemonitor.yaml"

echo "⏳ Waiting for deployments to be ready..."

# Wait for StatsD exporter
echo "Waiting for StatsD exporter..."
kubectl wait --for=condition=available --timeout=300s deployment/airflow-statsd-exporter -n "$NAMESPACE"

# Wait for PostgreSQL exporter
echo "Waiting for PostgreSQL exporter..."
kubectl wait --for=condition=available --timeout=300s deployment/postgresql-exporter -n "$NAMESPACE"

# Wait for Redis exporter
echo "Waiting for Redis exporter..."
kubectl wait --for=condition=available --timeout=300s deployment/redis-exporter -n "$NAMESPACE"

echo "✅ All monitoring components deployed successfully!"

echo ""
echo "📋 Deployment Summary:"
echo "- StatsD Exporter: Collects Airflow application metrics"
echo "- PostgreSQL Exporter: Collects database metrics"
echo "- Redis Exporter: Collects queue metrics"
echo "- ServiceMonitors: Enable Prometheus scraping"

echo ""
echo "🔍 Verification Commands:"
echo "kubectl get pods -n $NAMESPACE -l tier=monitoring"
echo "kubectl get servicemonitors -n $NAMESPACE"
echo "kubectl logs -n $NAMESPACE deployment/airflow-statsd-exporter"
echo "kubectl logs -n $NAMESPACE deployment/postgresql-exporter"
echo "kubectl logs -n $NAMESPACE deployment/redis-exporter"

echo ""
echo "📊 Metrics Endpoints:"
echo "- StatsD Exporter: http://airflow-statsd-exporter.airflow.svc.cluster.local:9102/metrics"
echo "- PostgreSQL Exporter: http://postgresql-exporter.airflow.svc.cluster.local:9187/metrics"
echo "- Redis Exporter: http://redis-metrics.airflow.svc.cluster.local:9121/metrics"

echo ""
echo "⚠️  Important Notes:"
echo "1. Update PostgreSQL exporter secret with actual database credentials"
echo "2. Ensure Airflow is redeployed with updated values to enable StatsD"
echo "3. Verify ServiceMonitors are discovered by Prometheus"
echo "4. Check Prometheus targets for scraping status"