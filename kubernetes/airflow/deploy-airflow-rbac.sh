#!/bin/bash

# Deploy Airflow Namespace and RBAC Configuration
# This script applies the namespace, service accounts, RBAC policies, and security configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="airflow"

echo "🚀 Deploying Airflow Namespace and RBAC Configuration..."

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if namespace exists
check_namespace() {
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo "✅ Namespace '$NAMESPACE' already exists"
        return 0
    else
        echo "ℹ️  Namespace '$NAMESPACE' does not exist, will be created"
        return 1
    fi
}

# Function to apply RBAC configuration
apply_rbac() {
    echo "📋 Applying Airflow namespace and RBAC configuration..."
    kubectl apply -f "$SCRIPT_DIR/airflow-namespace-rbac.yaml"
    
    echo "🔒 Applying security policies..."
    kubectl apply -f "$SCRIPT_DIR/airflow-security-policies.yaml"
}

# Function to verify deployment
verify_deployment() {
    echo "🔍 Verifying deployment..."
    
    # Check namespace
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo "✅ Namespace '$NAMESPACE' created successfully"
    else
        echo "❌ Failed to create namespace '$NAMESPACE'"
        return 1
    fi
    
    # Check service accounts
    local service_accounts=("airflow-webserver" "airflow-scheduler" "airflow-worker" "airflow-triggerer")
    for sa in "${service_accounts[@]}"; do
        if kubectl get serviceaccount "$sa" -n "$NAMESPACE" &> /dev/null; then
            echo "✅ ServiceAccount '$sa' created successfully"
        else
            echo "❌ Failed to create ServiceAccount '$sa'"
            return 1
        fi
    done
    
    # Check roles
    local roles=("airflow-webserver" "airflow-scheduler" "airflow-worker" "airflow-triggerer")
    for role in "${roles[@]}"; do
        if kubectl get role "$role" -n "$NAMESPACE" &> /dev/null; then
            echo "✅ Role '$role' created successfully"
        else
            echo "❌ Failed to create Role '$role'"
            return 1
        fi
    done
    
    # Check role bindings
    local rolebindings=("airflow-webserver" "airflow-scheduler" "airflow-worker" "airflow-triggerer")
    for rb in "${rolebindings[@]}"; do
        if kubectl get rolebinding "$rb" -n "$NAMESPACE" &> /dev/null; then
            echo "✅ RoleBinding '$rb' created successfully"
        else
            echo "❌ Failed to create RoleBinding '$rb'"
            return 1
        fi
    done
    
    # Check network policies
    local network_policies=("airflow-deny-all-ingress" "airflow-webserver-ingress" "airflow-scheduler-egress" "airflow-worker-egress" "airflow-webserver-egress" "airflow-monitoring-ingress" "postgresql-airflow-ingress" "redis-airflow-ingress")
    for np in "${network_policies[@]}"; do
        if kubectl get networkpolicy "$np" -n "$NAMESPACE" &> /dev/null; then
            echo "✅ NetworkPolicy '$np' created successfully"
        else
            echo "⚠️  NetworkPolicy '$np' may not be created (CNI might not support NetworkPolicies)"
        fi
    done
}

# Function to show status
show_status() {
    echo ""
    echo "📊 Current Airflow RBAC Status:"
    echo "================================"
    
    echo ""
    echo "Namespace:"
    kubectl get namespace "$NAMESPACE" -o wide 2>/dev/null || echo "❌ Namespace not found"
    
    echo ""
    echo "Service Accounts:"
    kubectl get serviceaccounts -n "$NAMESPACE" -l app.kubernetes.io/name=airflow 2>/dev/null || echo "❌ No service accounts found"
    
    echo ""
    echo "Roles:"
    kubectl get roles -n "$NAMESPACE" -l app.kubernetes.io/name=airflow 2>/dev/null || echo "❌ No roles found"
    
    echo ""
    echo "Role Bindings:"
    kubectl get rolebindings -n "$NAMESPACE" -l app.kubernetes.io/name=airflow 2>/dev/null || echo "❌ No role bindings found"
    
    echo ""
    echo "Network Policies:"
    kubectl get networkpolicies -n "$NAMESPACE" 2>/dev/null || echo "❌ No network policies found"
}

# Function to cleanup (for testing purposes)
cleanup() {
    echo "🧹 Cleaning up Airflow RBAC configuration..."
    kubectl delete -f "$SCRIPT_DIR/airflow-security-policies.yaml" --ignore-not-found=true
    kubectl delete -f "$SCRIPT_DIR/airflow-namespace-rbac.yaml" --ignore-not-found=true
    echo "✅ Cleanup completed"
}

# Main execution
main() {
    case "${1:-deploy}" in
        "deploy")
            check_kubectl
            apply_rbac
            verify_deployment
            show_status
            echo ""
            echo "🎉 Airflow RBAC configuration deployed successfully!"
            echo "ℹ️  You can now deploy Airflow components using the created service accounts."
            ;;
        "status")
            check_kubectl
            show_status
            ;;
        "cleanup")
            check_kubectl
            cleanup
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [deploy|status|cleanup|help]"
            echo ""
            echo "Commands:"
            echo "  deploy   - Deploy Airflow namespace and RBAC configuration (default)"
            echo "  status   - Show current RBAC status"
            echo "  cleanup  - Remove all RBAC configuration"
            echo "  help     - Show this help message"
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"