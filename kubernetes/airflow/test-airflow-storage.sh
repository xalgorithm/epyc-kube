#!/bin/bash

# Test Airflow Storage Configuration
# This script validates the persistent storage setup for Airflow
# Requirements: 2.2, 2.3, 2.6

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    print_test "Running: $test_name"
    
    if eval "$test_command" &> /dev/null; then
        print_status "✓ PASSED: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "✗ FAILED: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

print_status "Starting Airflow storage validation tests..."
print_status "=========================================="

# Test 1: Check if namespace exists
run_test "Airflow namespace exists" \
    "kubectl get namespace airflow"

# Test 2: Check PVC existence and status
run_test "DAGs PVC exists and bound" \
    "kubectl get pvc airflow-dags-pvc -n airflow -o jsonpath='{.status.phase}' | grep -q Bound"

run_test "Logs PVC exists and bound" \
    "kubectl get pvc airflow-logs-pvc -n airflow -o jsonpath='{.status.phase}' | grep -q Bound"

run_test "Config PVC exists and bound" \
    "kubectl get pvc airflow-config-pvc -n airflow -o jsonpath='{.status.phase}' | grep -q Bound"

# Test 3: Check PVC access modes
run_test "DAGs PVC has ReadWriteMany access" \
    "kubectl get pvc airflow-dags-pvc -n airflow -o jsonpath='{.spec.accessModes[0]}' | grep -q ReadWriteMany"

run_test "Logs PVC has ReadWriteMany access" \
    "kubectl get pvc airflow-logs-pvc -n airflow -o jsonpath='{.spec.accessModes[0]}' | grep -q ReadWriteMany"

run_test "Config PVC has ReadWriteMany access" \
    "kubectl get pvc airflow-config-pvc -n airflow -o jsonpath='{.spec.accessModes[0]}' | grep -q ReadWriteMany"

# Test 4: Check storage class
run_test "DAGs PVC uses nfs-client storage class" \
    "kubectl get pvc airflow-dags-pvc -n airflow -o jsonpath='{.spec.storageClassName}' | grep -q nfs-client"

run_test "Logs PVC uses nfs-client storage class" \
    "kubectl get pvc airflow-logs-pvc -n airflow -o jsonpath='{.spec.storageClassName}' | grep -q nfs-client"

run_test "Config PVC uses nfs-client storage class" \
    "kubectl get pvc airflow-config-pvc -n airflow -o jsonpath='{.spec.storageClassName}' | grep -q nfs-client"

# Test 5: Check storage capacity
run_test "DAGs PVC has correct capacity (50Gi)" \
    "kubectl get pvc airflow-dags-pvc -n airflow -o jsonpath='{.spec.resources.requests.storage}' | grep -q 50Gi"

run_test "Logs PVC has correct capacity (200Gi)" \
    "kubectl get pvc airflow-logs-pvc -n airflow -o jsonpath='{.spec.resources.requests.storage}' | grep -q 200Gi"

run_test "Config PVC has correct capacity (10Gi)" \
    "kubectl get pvc airflow-config-pvc -n airflow -o jsonpath='{.spec.resources.requests.storage}' | grep -q 10Gi"

# Test 6: Check monitoring components
run_test "Storage monitoring deployment exists" \
    "kubectl get deployment airflow-storage-exporter -n airflow"

run_test "Storage monitoring service exists" \
    "kubectl get service airflow-storage-exporter -n airflow"

run_test "Storage monitoring ServiceMonitor exists" \
    "kubectl get servicemonitor airflow-storage-monitor -n airflow"

run_test "Storage monitoring deployment is ready" \
    "kubectl get deployment airflow-storage-exporter -n airflow -o jsonpath='{.status.readyReplicas}' | grep -q 1"

# Test 7: Check alerting rules
run_test "Storage alerting PrometheusRule exists" \
    "kubectl get prometheusrule airflow-storage-alerts -n airflow"

# Test 8: Functional storage test
print_test "Running functional storage test..."
if kubectl run storage-functional-test --image=busybox --rm --restart=Never -n airflow \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "storage-test",
        "image": "busybox",
        "command": ["sh", "-c", "echo \"DAG test content\" > /dags/test-dag.py && echo \"Log test content\" > /logs/test.log && echo \"Config test content\" > /config/test.conf && ls -la /dags /logs /config && echo \"Storage test completed successfully\""],
        "volumeMounts": [
          {"name": "dags", "mountPath": "/dags"},
          {"name": "logs", "mountPath": "/logs"},
          {"name": "config", "mountPath": "/config"}
        ]
      }
    ],
    "volumes": [
      {"name": "dags", "persistentVolumeClaim": {"claimName": "airflow-dags-pvc"}},
      {"name": "logs", "persistentVolumeClaim": {"claimName": "airflow-logs-pvc"}},
      {"name": "config", "persistentVolumeClaim": {"claimName": "airflow-config-pvc"}}
    ]
  }
}' --timeout=60s; then
    print_status "✓ PASSED: Functional storage test"
    ((TESTS_PASSED++))
else
    print_error "✗ FAILED: Functional storage test"
    ((TESTS_FAILED++))
fi

# Test 9: Multi-pod access test
print_test "Running multi-pod access test..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod1
  namespace: airflow
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'Pod1 writing to DAGs' > /dags/pod1.txt && sleep 30"]
    volumeMounts:
    - name: dags
      mountPath: /dags
  volumes:
  - name: dags
    persistentVolumeClaim:
      claimName: airflow-dags-pvc
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod2
  namespace: airflow
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "sleep 10 && cat /dags/pod1.txt && echo 'Pod2 can read Pod1 file' > /dags/pod2.txt"]
    volumeMounts:
    - name: dags
      mountPath: /dags
  volumes:
  - name: dags
    persistentVolumeClaim:
      claimName: airflow-dags-pvc
  restartPolicy: Never
EOF

sleep 15

if kubectl wait --for=condition=Ready pod/storage-test-pod1 -n airflow --timeout=30s && \
   kubectl wait --for=condition=Ready pod/storage-test-pod2 -n airflow --timeout=30s; then
    print_status "✓ PASSED: Multi-pod access test"
    ((TESTS_PASSED++))
else
    print_error "✗ FAILED: Multi-pod access test"
    ((TESTS_FAILED++))
fi

# Cleanup test pods
kubectl delete pod storage-test-pod1 storage-test-pod2 -n airflow --ignore-not-found=true

# Test Summary
print_status ""
print_status "=========================================="
print_status "Test Summary:"
print_status "Tests Passed: $TESTS_PASSED"
print_status "Tests Failed: $TESTS_FAILED"
print_status "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"

if [ $TESTS_FAILED -eq 0 ]; then
    print_status "🎉 All tests passed! Airflow storage is properly configured."
    exit 0
else
    print_error "❌ Some tests failed. Please check the configuration."
    exit 1
fi