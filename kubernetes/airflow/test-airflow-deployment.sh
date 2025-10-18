#!/bin/bash

# Test script for Airflow Helm deployment
# This script validates the HA configuration and requirements compliance
# Requirements: 1.1, 1.2, 1.3, 1.4, 5.4

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="airflow"
RELEASE_NAME="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    print_status "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    if [[ "$result" -eq "$expected_result" ]]; then
        print_success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to run a test with warning on failure
run_test_warn() {
    local test_name="$1"
    local test_command="$2"
    
    print_status "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        print_success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        print_warning "$test_name"
        ((TESTS_WARNED++))
        return 1
    fi
}

# Test 1: Verify namespace exists
test_namespace() {
    run_test "Namespace '$NAMESPACE' exists" \
        "kubectl get namespace $NAMESPACE"
}

# Test 2: Verify Helm release exists
test_helm_release() {
    run_test "Helm release '$RELEASE_NAME' exists" \
        "helm list -n $NAMESPACE | grep -q $RELEASE_NAME"
}

# Test 3: Verify webserver HA (Requirement 1.1)
test_webserver_ha() {
    local replica_count
    replica_count=$(kubectl get deployment airflow-webserver -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$replica_count" -eq 2 ]]; then
        print_success "Webserver has 2 replicas (HA requirement 1.1)"
        ((TESTS_PASSED++))
    else
        print_error "Webserver has $replica_count replicas, expected 2 (HA requirement 1.1)"
        ((TESTS_FAILED++))
    fi
}

# Test 4: Verify scheduler HA (Requirement 1.2)
test_scheduler_ha() {
    local replica_count
    replica_count=$(kubectl get deployment airflow-scheduler -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$replica_count" -eq 2 ]]; then
        print_success "Scheduler has 2 replicas (HA requirement 1.2)"
        ((TESTS_PASSED++))
    else
        print_error "Scheduler has $replica_count replicas, expected 2 (HA requirement 1.2)"
        ((TESTS_FAILED++))
    fi
}

# Test 5: Verify webserver health checks (Requirement 1.3)
test_webserver_health_checks() {
    local liveness_probe
    local readiness_probe
    
    liveness_probe=$(kubectl get deployment airflow-webserver -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null || echo "")
    readiness_probe=$(kubectl get deployment airflow-webserver -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null || echo "")
    
    if [[ -n "$liveness_probe" && -n "$readiness_probe" ]]; then
        print_success "Webserver has health checks configured (requirement 1.3)"
        ((TESTS_PASSED++))
    else
        print_error "Webserver missing health checks (requirement 1.3)"
        ((TESTS_FAILED++))
    fi
}

# Test 6: Verify scheduler health checks (Requirement 1.4)
test_scheduler_health_checks() {
    local liveness_probe
    
    liveness_probe=$(kubectl get deployment airflow-scheduler -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null || echo "")
    
    if [[ -n "$liveness_probe" ]]; then
        print_success "Scheduler has health checks configured (requirement 1.4)"
        ((TESTS_PASSED++))
    else
        print_error "Scheduler missing health checks (requirement 1.4)"
        ((TESTS_FAILED++))
    fi
}

# Test 7: Verify CeleryKubernetesExecutor (Requirement 5.4)
test_executor_configuration() {
    run_test_warn "CeleryKubernetesExecutor configuration" \
        "kubectl get configmap airflow-config -n $NAMESPACE -o yaml | grep -q 'CeleryKubernetesExecutor'"
}

# Test 8: Verify worker deployment exists
test_worker_deployment() {
    run_test "Worker deployment exists" \
        "kubectl get deployment airflow-worker -n $NAMESPACE"
}

# Test 9: Verify resource limits are set
test_resource_limits() {
    local webserver_limits
    local scheduler_limits
    local worker_limits
    
    webserver_limits=$(kubectl get deployment airflow-webserver -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' 2>/dev/null || echo "")
    scheduler_limits=$(kubectl get deployment airflow-scheduler -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' 2>/dev/null || echo "")
    worker_limits=$(kubectl get deployment airflow-worker -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' 2>/dev/null || echo "")
    
    local all_have_limits=true
    
    if [[ -z "$webserver_limits" ]]; then
        print_error "Webserver missing resource limits"
        all_have_limits=false
    fi
    
    if [[ -z "$scheduler_limits" ]]; then
        print_error "Scheduler missing resource limits"
        all_have_limits=false
    fi
    
    if [[ -z "$worker_limits" ]]; then
        print_error "Worker missing resource limits"
        all_have_limits=false
    fi
    
    if [[ "$all_have_limits" == true ]]; then
        print_success "All components have resource limits configured"
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
}

# Test 10: Verify pods are running
test_pods_running() {
    local webserver_ready
    local scheduler_ready
    local worker_ready
    
    webserver_ready=$(kubectl get pods -n "$NAMESPACE" -l component=webserver --no-headers | grep -c "Running" || echo "0")
    scheduler_ready=$(kubectl get pods -n "$NAMESPACE" -l component=scheduler --no-headers | grep -c "Running" || echo "0")
    worker_ready=$(kubectl get pods -n "$NAMESPACE" -l component=worker --no-headers | grep -c "Running" || echo "0")
    
    if [[ "$webserver_ready" -ge 1 && "$scheduler_ready" -ge 1 && "$worker_ready" -ge 1 ]]; then
        print_success "All Airflow components have running pods"
        ((TESTS_PASSED++))
    else
        print_error "Some Airflow components are not running (webserver: $webserver_ready, scheduler: $scheduler_ready, worker: $worker_ready)"
        ((TESTS_FAILED++))
    fi
}

# Test 11: Verify database connectivity
test_database_connectivity() {
    run_test_warn "Database connectivity from scheduler" \
        "kubectl exec -n $NAMESPACE deployment/airflow-scheduler -- airflow db check"
}

# Test 12: Verify Redis connectivity
test_redis_connectivity() {
    run_test_warn "Redis connectivity" \
        "kubectl exec -n $NAMESPACE deployment/airflow-scheduler -- python -c 'import redis; r=redis.Redis(host=\"redis\", port=6379, password=\"airflow-redis-2024\"); r.ping()'"
}

# Test 13: Verify service accounts
test_service_accounts() {
    run_test "Airflow service account exists" \
        "kubectl get serviceaccount airflow-scheduler -n $NAMESPACE"
}

# Test 14: Verify persistent volume claims
test_persistent_volumes() {
    run_test "DAGs PVC exists and bound" \
        "kubectl get pvc airflow-dags-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"
    
    run_test "Logs PVC exists and bound" \
        "kubectl get pvc airflow-logs-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"
}

# Test 15: Verify webserver service
test_webserver_service() {
    run_test "Webserver service exists" \
        "kubectl get service airflow-webserver -n $NAMESPACE"
}

# Function to display test summary
display_summary() {
    echo
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Tests Warned: $TESTS_WARNED"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED))"
    echo
    
    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        print_success "All critical tests passed!"
        if [[ "$TESTS_WARNED" -gt 0 ]]; then
            print_warning "Some non-critical tests had warnings"
        fi
        return 0
    else
        print_error "Some tests failed. Please check the deployment."
        return 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "Airflow Deployment Test Suite"
    echo "Task 5: Deploy Airflow using Helm chart with HA configuration"
    echo "=========================================="
    echo
    
    # Run all tests
    test_namespace
    test_helm_release
    test_webserver_ha
    test_scheduler_ha
    test_webserver_health_checks
    test_scheduler_health_checks
    test_executor_configuration
    test_worker_deployment
    test_resource_limits
    test_pods_running
    test_database_connectivity
    test_redis_connectivity
    test_service_accounts
    test_persistent_volumes
    test_webserver_service
    
    # Display summary
    display_summary
}

# Run main function
main "$@"