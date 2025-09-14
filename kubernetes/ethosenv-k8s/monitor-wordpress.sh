#!/bin/bash

# Monitor WordPress Kubernetes Deployment
# This script monitors the WordPress deployment status and provides health information

set -euo pipefail

NAMESPACE="ethosenv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check pod status
check_pod_status() {
    echo ""
    echo "📊 Pod Status:"
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$pods" ]]; then
        log_warning "No pods found in namespace $NAMESPACE"
        return 1
    fi
    
    for pod in $pods; do
        local status
        status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        local ready
        ready=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        local restarts
        restarts=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
        
        case "$status" in
            "Running")
                if [[ "$ready" == "true" ]]; then
                    echo "✅ $pod: Running and Ready (restarts: $restarts)"
                else
                    echo "⏳ $pod: Running but Not Ready (restarts: $restarts)"
                fi
                ;;
            "Pending")
                echo "⏳ $pod: Pending"
                ;;
            "Failed"|"Error")
                echo "❌ $pod: $status"
                ;;
            *)
                echo "🔄 $pod: $status"
                ;;
        esac
    done
}

# Function to check services
check_services() {
    echo ""
    echo "🌐 Service Status:"
    
    local services=("wordpress" "mysql")
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            local endpoints
            endpoints=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
            if [[ -n "$endpoints" ]]; then
                local endpoint_count
                endpoint_count=$(echo "$endpoints" | wc -w)
                echo "✅ $service: Ready ($endpoint_count endpoints)"
            else
                echo "⏳ $service: No endpoints ready"
            fi
        else
            echo "❌ $service: Not found"
        fi
    done
}

# Function to check storage
check_storage() {
    echo ""
    echo "💾 Storage Status:"
    
    local pvcs=("wordpress-pvc" "mysql-pvc")
    
    for pvc in "${pvcs[@]}"; do
        if kubectl get pvc "$pvc" -n "$NAMESPACE" >/dev/null 2>&1; then
            local status
            status=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            local capacity
            capacity=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}' 2>/dev/null || echo "Unknown")
            
            case "$status" in
                "Bound")
                    echo "✅ $pvc: Bound ($capacity)"
                    ;;
                "Pending")
                    echo "⏳ $pvc: Pending"
                    ;;
                *)
                    echo "❌ $pvc: $status"
                    ;;
            esac
        else
            echo "❌ $pvc: Not found"
        fi
    done
}

# Function to check ingress
check_ingress() {
    echo ""
    echo "🔗 Ingress Status:"
    
    if kubectl get ingress wordpress-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
        local hosts
        hosts=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.spec.rules[*].host}' 2>/dev/null || echo "")
        local ip
        ip=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        local tls_secret
        tls_secret=$(kubectl get ingress wordpress-ingress -n "$NAMESPACE" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || echo "")
        
        if [[ -n "$ip" ]]; then
            echo "✅ wordpress-ingress: Ready"
            echo "   Hosts: $hosts"
            echo "   IP: $ip"
            if [[ -n "$tls_secret" ]]; then
                echo "   TLS: $tls_secret"
            fi
        else
            echo "⏳ wordpress-ingress: Waiting for IP assignment"
            echo "   Hosts: $hosts"
            if [[ -n "$tls_secret" ]]; then
                echo "   TLS: $tls_secret"
            fi
        fi
    else
        echo "❌ wordpress-ingress: Not found"
    fi
}

# Function to check SSL certificate
check_ssl_certificate() {
    echo ""
    echo "🔐 SSL Certificate Status:"
    
    if kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" >/dev/null 2>&1; then
        local cert_status
        cert_status=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        local cert_reason
        cert_reason=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
        
        case "$cert_status" in
            "True")
                echo "✅ SSL Certificate: Ready"
                local expiry
                expiry=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.notAfter}' 2>/dev/null || echo "Unknown")
                echo "   Expires: $expiry"
                ;;
            "False")
                if [[ "$cert_reason" == "Issuing" ]]; then
                    echo "⏳ SSL Certificate: Being issued"
                else
                    echo "❌ SSL Certificate: Failed ($cert_reason)"
                fi
                ;;
            *)
                echo "🔄 SSL Certificate: $cert_status ($cert_reason)"
                ;;
        esac
        
        # Check TLS secret
        if kubectl get secret ethos-tls-secret -n "$NAMESPACE" >/dev/null 2>&1; then
            echo "✅ TLS Secret: Present"
        else
            echo "❌ TLS Secret: Missing"
        fi
    else
        echo "❌ SSL Certificate: Not found"
    fi
}

# Function to test connectivity
test_connectivity() {
    echo ""
    echo "🔍 Connectivity Tests:"
    
    # Test MySQL connectivity
    local mysql_pod
    mysql_pod=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$mysql_pod" ]]; then
        if kubectl exec -n "$NAMESPACE" "$mysql_pod" -- mysqladmin ping -h localhost >/dev/null 2>&1; then
            echo "✅ MySQL: Database is responding"
        else
            echo "❌ MySQL: Database is not responding"
        fi
    else
        echo "❌ MySQL: Pod not found"
    fi
    
    # Test WordPress connectivity
    local wordpress_pod
    wordpress_pod=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$wordpress_pod" ]]; then
        if kubectl exec -n "$NAMESPACE" "$wordpress_pod" -- curl -s -o /dev/null -w "%{http_code}" http://localhost >/dev/null 2>&1; then
            echo "✅ WordPress: Web server is responding"
        else
            echo "❌ WordPress: Web server is not responding"
        fi
    else
        echo "❌ WordPress: Pod not found"
    fi
}

# Function to show resource usage
show_resource_usage() {
    echo ""
    echo "📈 Resource Usage:"
    
    if command -v kubectl-top >/dev/null 2>&1 || kubectl top nodes >/dev/null 2>&1; then
        echo "Pod Resource Usage:"
        kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics not available"
    else
        echo "Resource metrics not available (metrics-server not installed)"
    fi
}

# Function to show recent events
show_recent_events() {
    echo ""
    echo "📋 Recent Events:"
    
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
}

# Main monitoring function
main() {
    clear
    echo "🚀 WordPress Kubernetes Deployment Monitor"
    echo "Namespace: $NAMESPACE"
    echo "Time: $(date)"
    echo "=========================================="
    
    check_pod_status
    check_services
    check_storage
    check_ingress
    check_ssl_certificate
    test_connectivity
    show_resource_usage
    show_recent_events
    
    echo ""
    echo "🔗 Quick Access Commands:"
    echo "Port forward WordPress: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
    echo "Port forward MySQL: kubectl port-forward svc/mysql 3306:3306 -n $NAMESPACE"
    echo "WordPress shell: kubectl exec -it deployment/wordpress -n $NAMESPACE -- bash"
    echo "MySQL shell: kubectl exec -it deployment/mysql -n $NAMESPACE -- mysql -u root -proot_password"
    
    echo ""
    echo "📊 Detailed Status Commands:"
    echo "kubectl get all -n $NAMESPACE"
    echo "kubectl describe pods -n $NAMESPACE"
    echo "kubectl logs -f deployment/wordpress -n $NAMESPACE"
    echo "kubectl logs -f deployment/mysql -n $NAMESPACE"
}

# Check if watch mode is requested
if [[ "${1:-}" == "watch" ]]; then
    while true; do
        main
        echo ""
        echo "⏳ Refreshing in 30 seconds... (Ctrl+C to exit)"
        sleep 30
    done
else
    main
fi