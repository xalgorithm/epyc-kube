#!/bin/bash

# Deploy Airflow Network Policies
# This script applies network security policies for the Airflow deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="airflow"

echo "🔒 Deploying Airflow Network Policies..."

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo "❌ Namespace '$NAMESPACE' does not exist"
        echo "ℹ️  Please run './deploy-airflow-rbac.sh' first to create the namespace"
        exit 1
    fi
    echo "✅ Namespace '$NAMESPACE' exists"
}

# Function to check CNI support for NetworkPolicies
check_network_policy_support() {
    echo "🔍 Checking if CNI supports NetworkPolicies..."
    
    # Try to create a test network policy
    local test_policy=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-netpol
  namespace: default
spec:
  podSelector: {}
  policyTypes: []
EOF
)
    
    if ! echo "$test_policy" | kubectl apply -f - &> /dev/null; then
        echo "⚠️  Warning: CNI does not support NetworkPolicies"
        echo "ℹ️  Network policies will be created but may not be enforced"
        echo "ℹ️  Consider using a CNI that supports NetworkPolicies (e.g., Calico, Cilium)"
        return 1
    fi
    
    kubectl delete networkpolicy test-netpol -n default &> /dev/null || true
    echo "✅ CNI supports NetworkPolicies"
    return 0
}

# Function to apply network policies
apply_network_policies() {
    echo "📋 Applying Airflow network policies..."
    
    # Extract only the NetworkPolicy resources from the security policies file
    kubectl apply -f "$SCRIPT_DIR/airflow-security-policies.yaml"
    
    echo "✅ Network policies applied successfully"
}

# Function to verify network policies
verify_network_policies() {
    echo "🔍 Verifying network policies..."
    
    local policies=("airflow-deny-all-ingress" "airflow-webserver-ingress" "airflow-scheduler-egress" 
                   "airflow-worker-egress" "airflow-webserver-egress" "airflow-monitoring-ingress" 
                   "postgresql-airflow-ingress" "redis-airflow-ingress")
    
    local success_count=0
    local total_count=${#policies[@]}
    
    for policy in "${policies[@]}"; do
        if kubectl get networkpolicy "$policy" -n "$NAMESPACE" &> /dev/null; then
            echo "✅ NetworkPolicy '$policy' deployed successfully"
            ((success_count++))
        else
            echo "❌ NetworkPolicy '$policy' failed to deploy"
        fi
    done
    
    echo ""
    echo "📊 Deployment Summary: $success_count/$total_count network policies deployed"
    
    if [ $success_count -eq $total_count ]; then
        echo "🎉 All network policies deployed successfully!"
        return 0
    else
        echo "⚠️  Some network policies failed to deploy"
        return 1
    fi
}

# Function to show network policy status
show_status() {
    echo ""
    echo "📊 Network Policy Status:"
    echo "========================"
    
    echo ""
    echo "All Network Policies:"
    kubectl get networkpolicies -n "$NAMESPACE" -o wide 2>/dev/null || echo "❌ No network policies found"
    
    echo ""
    echo "Network Policy Details:"
    echo "======================"
    
    local key_policies=("airflow-deny-all-ingress" "airflow-webserver-ingress" "airflow-monitoring-ingress")
    
    for policy in "${key_policies[@]}"; do
        if kubectl get networkpolicy "$policy" -n "$NAMESPACE" &> /dev/null; then
            echo ""
            echo "🔒 $policy:"
            echo "   Selector: $(kubectl get networkpolicy "$policy" -n "$NAMESPACE" -o jsonpath='{.spec.podSelector}')"
            echo "   Policy Types: $(kubectl get networkpolicy "$policy" -n "$NAMESPACE" -o jsonpath='{.spec.policyTypes[*]}')"
            
            # Show ingress rules if they exist
            local ingress_count
            ingress_count=$(kubectl get networkpolicy "$policy" -n "$NAMESPACE" -o jsonpath='{.spec.ingress}' | jq '. | length' 2>/dev/null || echo "0")
            if [ "$ingress_count" != "null" ] && [ "$ingress_count" -gt 0 ]; then
                echo "   Ingress Rules: $ingress_count rule(s)"
            fi
            
            # Show egress rules if they exist
            local egress_count
            egress_count=$(kubectl get networkpolicy "$policy" -n "$NAMESPACE" -o jsonpath='{.spec.egress}' | jq '. | length' 2>/dev/null || echo "0")
            if [ "$egress_count" != "null" ] && [ "$egress_count" -gt 0 ]; then
                echo "   Egress Rules: $egress_count rule(s)"
            fi
        fi
    done
}

# Function to test network policies
test_policies() {
    echo "🧪 Running network policy tests..."
    
    if [ -f "$SCRIPT_DIR/test-airflow-network-policies.sh" ]; then
        "$SCRIPT_DIR/test-airflow-network-policies.sh" test
    else
        echo "⚠️  Test script not found - skipping tests"
        echo "ℹ️  You can manually verify network policies using kubectl"
    fi
}

# Function to cleanup network policies
cleanup() {
    echo "🧹 Removing Airflow network policies..."
    
    local policies=("airflow-deny-all-ingress" "airflow-webserver-ingress" "airflow-scheduler-egress" 
                   "airflow-worker-egress" "airflow-webserver-egress" "airflow-monitoring-ingress" 
                   "postgresql-airflow-ingress" "redis-airflow-ingress")
    
    for policy in "${policies[@]}"; do
        kubectl delete networkpolicy "$policy" -n "$NAMESPACE" --ignore-not-found=true
        echo "🗑️  Removed NetworkPolicy '$policy'"
    done
    
    echo "✅ Network policies cleanup completed"
}

# Function to show help
show_help() {
    echo "Usage: $0 [deploy|status|test|cleanup|help]"
    echo ""
    echo "Commands:"
    echo "  deploy   - Deploy network policies (default)"
    echo "  status   - Show current network policy status"
    echo "  test     - Run network policy tests"
    echo "  cleanup  - Remove all network policies"
    echo "  help     - Show this help message"
    echo ""
    echo "Network Policies Deployed:"
    echo "  • airflow-deny-all-ingress     - Deny all ingress traffic by default"
    echo "  • airflow-webserver-ingress    - Allow ingress to webserver from ingress controller"
    echo "  • airflow-scheduler-egress     - Allow scheduler to communicate with database/Redis/workers"
    echo "  • airflow-worker-egress        - Allow workers to communicate with database/Redis"
    echo "  • airflow-webserver-egress     - Allow webserver to communicate with database/Redis"
    echo "  • airflow-monitoring-ingress   - Allow monitoring access from monitoring namespace"
    echo "  • postgresql-airflow-ingress   - Allow database access from Airflow components"
    echo "  • redis-airflow-ingress        - Allow Redis access from Airflow components"
    echo ""
    echo "Prerequisites:"
    echo "  • Kubernetes cluster with NetworkPolicy support (CNI like Calico, Cilium)"
    echo "  • Airflow namespace must exist (run deploy-airflow-rbac.sh first)"
    echo "  • kubectl configured to access the cluster"
}

# Main execution
main() {
    case "${1:-deploy}" in
        "deploy")
            check_kubectl
            check_namespace
            check_network_policy_support
            apply_network_policies
            verify_network_policies
            show_status
            echo ""
            echo "🎉 Network policies deployed successfully!"
            echo "ℹ️  Run '$0 test' to validate the policies are working correctly"
            ;;
        "status")
            check_kubectl
            check_namespace
            show_status
            ;;
        "test")
            check_kubectl
            check_namespace
            test_policies
            ;;
        "cleanup")
            check_kubectl
            cleanup
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"