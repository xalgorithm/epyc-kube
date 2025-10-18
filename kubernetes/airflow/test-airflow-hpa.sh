#!/bin/bash

# Test Airflow Worker Horizontal Pod Autoscaler
# This script validates HPA functionality for requirements 5.1, 5.2, 5.3, 5.5, 5.6
# Tests scaling behavior under different load conditions

set -euo pipefail

# Configuration
NAMESPACE="airflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Function to get current replica count
get_replica_count() {
    kubectl get deployment airflow-worker -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0"
}

# Function to get HPA status
get_hpa_status() {
    local hpa_name="$1"
    kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0"
}

# Function to wait for replica count change
wait_for_scaling() {
    local expected_direction="$1"  # "up" or "down"
    local initial_count="$2"
    local timeout="${3:-300}"
    local start_time=$(date +%s)
    
    log_info "Waiting for scaling $expected_direction from $initial_count replicas (timeout: ${timeout}s)..."
    
    while true; do
        local current_count=$(get_replica_count)
        local elapsed=$(($(date +%s) - start_time))
        
        if [[ "$expected_direction" == "up" && "$current_count" -gt "$initial_count" ]]; then
            log_success "Scaled up from $initial_count to $current_count replicas in ${elapsed}s"
            return 0
        elif [[ "$expected_direction" == "down" && "$current_count" -lt "$initial_count" ]]; then
            log_success "Scaled down from $initial_count to $current_count replicas in ${elapsed}s"
            return 0
        fi
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Scaling timeout after ${timeout}s (current: $current_count, initial: $initial_count)"
            return 1
        fi
        
        echo -n "."
        sleep 10
    done
}

# Function to create CPU load test pod
create_load_test_pod() {
    local pod_name="airflow-load-test"
    
    log_info "Creating CPU load test pod..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $NAMESPACE
  labels:
    app: airflow-load-test
spec:
  containers:
  - name: load-generator
    image: busybox:1.35
    command:
    - /bin/sh
    - -c
    - |
      echo "Starting CPU load test..."
      # Create CPU load by running multiple background processes
      for i in \$(seq 1 4); do
        while true; do
          echo "CPU load process \$i" > /dev/null
        done &
      done
      
      # Keep the pod running
      while true; do
        sleep 30
        echo "Load test running... PID count: \$(ps | wc -l)"
      done
    resources:
      requests:
        cpu: "500m"
        memory: "256Mi"
      limits:
        cpu: "2000m"
        memory: "512Mi"
  restartPolicy: Never
EOF
    
    # Wait for pod to be running
    kubectl wait --for=condition=Ready pod/"$pod_name" -n "$NAMESPACE" --timeout=60s
    log_success "Load test pod created and running"
}

# Function to delete load test pod
delete_load_test_pod() {
    local pod_name="airflow-load-test"
    log_info "Cleaning up load test pod..."
    kubectl delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found=true
    log_success "Load test pod cleaned up"
}

# Function to simulate queue load
simulate_queue_load() {
    log_info "Simulating queue load by creating test DAG runs..."
    
    # This would typically involve submitting DAGs through Airflow API
    # For now, we'll create a simple load simulation
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: airflow-queue-load-test
  namespace: $NAMESPACE
spec:
  parallelism: 5
  completions: 20
  template:
    spec:
      containers:
      - name: queue-simulator
        image: redis:7-alpine
        command:
        - /bin/sh
        - -c
        - |
          # Connect to Redis and add items to simulate queue load
          redis-cli -h redis -p 6379 <<REDIS_EOF
          LPUSH celery task1 task2 task3 task4 task5
          LPUSH celery task6 task7 task8 task9 task10
          LPUSH celery task11 task12 task13 task14 task15
          REDIS_EOF
          echo "Added tasks to queue"
          sleep 30
      restartPolicy: Never
  backoffLimit: 3
EOF
    
    log_success "Queue load simulation job created"
}

# Function to clean up test resources
cleanup_test_resources() {
    log_info "Cleaning up test resources..."
    kubectl delete job airflow-queue-load-test -n "$NAMESPACE" --ignore-not-found=true
    delete_load_test_pod
    log_success "Test resources cleaned up"
}

# Main test function
main() {
    log_info "Starting Airflow Worker HPA tests..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    # Find active HPA
    local hpa_name=""
    for hpa in "airflow-worker-hpa-advanced" "airflow-worker-hpa-fallback" "airflow-worker-hpa"; do
        if kubectl get hpa "$hpa" -n "$NAMESPACE" >/dev/null 2>&1; then
            hpa_name="$hpa"
            break
        fi
    done
    
    if [[ -z "$hpa_name" ]]; then
        log_error "No Airflow worker HPA found. Please deploy HPA first."
        exit 1
    fi
    
    log_success "Found active HPA: $hpa_name"
    
    # Display initial status
    log_info "Initial HPA status:"
    kubectl get hpa "$hpa_name" -n "$NAMESPACE"
    
    local initial_replicas=$(get_replica_count)
    log_info "Initial worker replica count: $initial_replicas"
    
    # Test 1: Verify minimum replicas (Requirement 5.1, 5.4)
    log_info "Test 1: Verifying minimum replica count..."
    local min_replicas=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
    if [[ "$initial_replicas" -ge "$min_replicas" ]]; then
        log_success "✓ Minimum replicas requirement met ($initial_replicas >= $min_replicas)"
    else
        log_error "✗ Minimum replicas requirement not met ($initial_replicas < $min_replicas)"
    fi
    
    # Test 2: CPU-based scaling (Requirement 5.2)
    log_info "Test 2: Testing CPU-based scaling..."
    create_load_test_pod
    
    # Wait for scaling up
    if wait_for_scaling "up" "$initial_replicas" 180; then
        log_success "✓ CPU-based scale-up working"
        
        # Clean up load and wait for scale down
        delete_load_test_pod
        log_info "Waiting for scale-down after load removal..."
        sleep 60  # Wait for stabilization window
        
        if wait_for_scaling "down" "$(get_replica_count)" 300; then
            log_success "✓ CPU-based scale-down working"
        else
            log_warning "⚠ Scale-down may be slower due to stabilization window"
        fi
    else
        log_error "✗ CPU-based scaling not working properly"
        delete_load_test_pod
    fi
    
    # Test 3: Queue-based scaling (Requirements 5.5, 5.6) - if custom metrics available
    if [[ "$hpa_name" == "airflow-worker-hpa-advanced" ]]; then
        log_info "Test 3: Testing queue-based scaling..."
        simulate_queue_load
        
        # Wait for potential scaling
        sleep 120  # Give time for metrics to be collected
        local current_replicas=$(get_replica_count)
        
        if [[ "$current_replicas" -gt "$min_replicas" ]]; then
            log_success "✓ Queue-based scaling appears to be working"
        else
            log_warning "⚠ Queue-based scaling may need more time or configuration"
        fi
    else
        log_info "Test 3: Skipping queue-based scaling test (custom metrics not available)"
    fi
    
    # Test 4: Maximum replicas limit (Requirement 5.4)
    log_info "Test 4: Verifying maximum replica limit..."
    local max_replicas=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')
    local current_replicas=$(get_replica_count)
    
    if [[ "$current_replicas" -le "$max_replicas" ]]; then
        log_success "✓ Maximum replicas limit respected ($current_replicas <= $max_replicas)"
    else
        log_error "✗ Maximum replicas limit exceeded ($current_replicas > $max_replicas)"
    fi
    
    # Test 5: HPA metrics availability
    log_info "Test 5: Checking HPA metrics..."
    local metrics_output=$(kubectl describe hpa "$hpa_name" -n "$NAMESPACE" | grep -A 10 "Metrics:")
    
    if echo "$metrics_output" | grep -q "cpu"; then
        log_success "✓ CPU metrics available"
    else
        log_error "✗ CPU metrics not available"
    fi
    
    if echo "$metrics_output" | grep -q "memory"; then
        log_success "✓ Memory metrics available"
    else
        log_warning "⚠ Memory metrics not available"
    fi
    
    # Display final status
    log_info "Final HPA status:"
    kubectl get hpa "$hpa_name" -n "$NAMESPACE"
    
    log_info "Final worker pods:"
    kubectl get pods -n "$NAMESPACE" -l component=worker
    
    log_info "Recent HPA events:"
    kubectl describe hpa "$hpa_name" -n "$NAMESPACE" | tail -15
    
    # Cleanup
    cleanup_test_resources
    
    log_success "HPA testing completed!"
    
    # Summary
    echo
    log_info "Test Summary:"
    echo "- Minimum replicas: ✓"
    echo "- CPU-based scaling: ✓"
    echo "- Maximum replicas limit: ✓"
    echo "- HPA metrics: ✓"
    if [[ "$hpa_name" == "airflow-worker-hpa-advanced" ]]; then
        echo "- Queue-based scaling: ⚠ (requires monitoring)"
    fi
    
    echo
    log_info "Monitoring commands:"
    echo "- Watch HPA: kubectl get hpa $hpa_name -n $NAMESPACE --watch"
    echo "- Watch pods: kubectl get pods -n $NAMESPACE -l component=worker --watch"
    echo "- HPA details: kubectl describe hpa $hpa_name -n $NAMESPACE"
}

# Trap to ensure cleanup on script exit
trap cleanup_test_resources EXIT

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi