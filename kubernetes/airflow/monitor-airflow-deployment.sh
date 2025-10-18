#!/bin/bash

# Monitor Airflow Deployment Status
# This script monitors the Airflow deployment progress and provides status updates

set -euo pipefail

NAMESPACE="airflow"

echo "🔍 Monitoring Airflow Deployment Status..."

# Function to check pod status
check_pod_status() {
    echo ""
    echo "📊 Current Pod Status:"
    kubectl get pods -n "$NAMESPACE" | grep airflow | while read -r line; do
        pod_name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $3}')
        restarts=$(echo "$line" | awk '{print $4}')
        
        case "$status" in
            "Running")
                echo "✅ $pod_name: $status (restarts: $restarts)"
                ;;
            "Init:"*)
                echo "⏳ $pod_name: $status (waiting for init containers)"
                ;;
            "CreateContainerConfigError"|"Error"|"CrashLoopBackOff")
                echo "❌ $pod_name: $status"
                ;;
            *)
                echo "🔄 $pod_name: $status"
                ;;
        esac
    done
}

# Function to check secrets
check_secrets() {
    echo ""
    echo "🔐 Checking Required Secrets:"
    
    local required_secrets=("airflow-database-secret" "airflow-redis-secret" "airflow-webserver-secret" "airflow-connections-secret")
    
    for secret in "${required_secrets[@]}"; do
        if kubectl get secret "$secret" -n "$NAMESPACE" >/dev/null 2>&1; then
            echo "✅ $secret: exists"
        else
            echo "❌ $secret: missing"
        fi
    done
}

# Function to check database connectivity
check_database() {
    echo ""
    echo "🗄️ Checking Database Status:"
    
    if kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -c "SELECT 1;" >/dev/null 2>&1; then
        echo "✅ Database connection: working"
        
        # Check if Airflow tables exist
        local table_count
        table_count=$(kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U airflow -d airflow -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' \n' || echo "0")
        
        if [[ "$table_count" -gt 0 ]]; then
            echo "✅ Airflow tables: $table_count tables found (migrations completed)"
        else
            echo "⏳ Airflow tables: none found (migrations in progress)"
        fi
    else
        echo "❌ Database connection: failed"
    fi
}

# Function to check Redis connectivity
check_redis() {
    echo ""
    echo "🔄 Checking Redis Status:"
    
    if kubectl exec -n "$NAMESPACE" redis-0 -c redis -- redis-cli -a airflow-redis-2024 ping >/dev/null 2>&1; then
        echo "✅ Redis connection: working"
    else
        echo "❌ Redis connection: failed"
    fi
}

# Function to check services
check_services() {
    echo ""
    echo "🌐 Checking Services:"
    
    local services=("airflow-api-server" "airflow-webserver" "airflow-flower" "airflow-statsd")
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            local endpoints
            endpoints=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
            if [[ -n "$endpoints" ]]; then
                echo "✅ $service: ready (endpoints: $(echo "$endpoints" | wc -w))"
            else
                echo "⏳ $service: no endpoints ready"
            fi
        else
            echo "❌ $service: not found"
        fi
    done
}

# Main monitoring loop
main() {
    local max_iterations=20
    local iteration=0
    
    while [[ $iteration -lt $max_iterations ]]; do
        clear
        echo "🚀 Airflow Deployment Monitor - Iteration $((iteration + 1))/$max_iterations"
        echo "Time: $(date)"
        
        check_secrets
        check_database
        check_redis
        check_services
        check_pod_status
        
        echo ""
        echo "📋 Summary:"
        local running_pods
        running_pods=$(kubectl get pods -n "$NAMESPACE" | grep airflow | grep -c "Running" || echo "0")
        local total_pods
        total_pods=$(kubectl get pods -n "$NAMESPACE" | grep airflow | wc -l || echo "0")
        
        echo "Running pods: $running_pods/$total_pods"
        
        # Check if deployment is complete
        if [[ "$running_pods" -gt 5 ]]; then
            echo ""
            echo "🎉 Airflow deployment appears to be successful!"
            echo ""
            echo "🔗 Access URLs:"
            echo "Airflow UI: kubectl port-forward svc/airflow-webserver 8080:8080 -n $NAMESPACE"
            echo "Flower UI: kubectl port-forward svc/airflow-flower 5555:5555 -n $NAMESPACE"
            echo "API Server: kubectl port-forward svc/airflow-api-server 8080:8080 -n $NAMESPACE"
            echo ""
            echo "👤 Default Credentials:"
            echo "Username: admin"
            echo "Password: admin"
            break
        fi
        
        if [[ $iteration -lt $((max_iterations - 1)) ]]; then
            echo ""
            echo "⏳ Waiting 30 seconds before next check..."
            sleep 30
        fi
        
        iteration=$((iteration + 1))
    done
    
    if [[ $iteration -eq $max_iterations ]]; then
        echo ""
        echo "⚠️  Monitoring completed. Check individual pod logs for issues:"
        kubectl get pods -n "$NAMESPACE" | grep airflow | grep -v Running | awk '{print $1}' | while read -r pod; do
            echo "kubectl logs $pod -n $NAMESPACE"
        done
    fi
}

# Run the monitor
main