#!/bin/bash

# Verify WordPress Kubernetes Deployment
# This script performs comprehensive verification of the WordPress deployment

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

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo "✅ PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "❌ FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "🧪 WordPress Kubernetes Deployment Verification"
echo "Namespace: $NAMESPACE"
echo "=============================================="

# Test 1: Namespace exists
run_test "Namespace exists" "kubectl get namespace $NAMESPACE"

# Test 2: Secrets exist
run_test "WordPress secrets exist" "kubectl get secret wordpress-secrets -n $NAMESPACE"
run_test "MySQL secrets exist" "kubectl get secret mysql-secrets -n $NAMESPACE"

# Test 3: PVCs are bound
run_test "WordPress PVC is bound" "kubectl get pvc wordpress-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"
run_test "MySQL PVC is bound" "kubectl get pvc mysql-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"

# Test 4: Deployments are ready
run_test "MySQL deployment is ready" "kubectl wait --for=condition=available --timeout=60s deployment/mysql -n $NAMESPACE"
run_test "WordPress deployment is ready" "kubectl wait --for=condition=available --timeout=60s deployment/wordpress -n $NAMESPACE"

# Test 5: Pods are running
run_test "MySQL pod is running" "kubectl get pod -n $NAMESPACE -l app=mysql -o jsonpath='{.items[0].status.phase}' | grep -q Running"
run_test "WordPress pod is running" "kubectl get pod -n $NAMESPACE -l app=wordpress -o jsonpath='{.items[0].status.phase}' | grep -q Running"

# Test 6: Services have endpoints
run_test "MySQL service has endpoints" "kubectl get endpoints mysql -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[0].ip}' | grep -q ."
run_test "WordPress service has endpoints" "kubectl get endpoints wordpress -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[0].ip}' | grep -q ."

# Test 7: Database connectivity
mysql_pod=$(kubectl get pod -n "$NAMESPACE" -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$mysql_pod" ]]; then
    run_test "MySQL database is responding" "kubectl exec -n $NAMESPACE $mysql_pod -- mysqladmin ping -h localhost"
    run_test "WordPress database exists" "kubectl exec -n $NAMESPACE $mysql_pod -- mysql -u root -proot_password -e 'USE wordpress; SELECT 1;'"
else
    log_error "MySQL pod not found for connectivity tests"
    TESTS_FAILED=$((TESTS_FAILED + 2))
    TESTS_TOTAL=$((TESTS_TOTAL + 2))
fi

# Test 8: WordPress connectivity
wordpress_pod=$(kubectl get pod -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$wordpress_pod" ]]; then
    run_test "WordPress web server is responding" "kubectl exec -n $NAMESPACE $wordpress_pod -- curl -s -o /dev/null -w '%{http_code}' http://localhost | grep -q 200"
    run_test "WordPress files are present" "kubectl exec -n $NAMESPACE $wordpress_pod -- test -f /var/www/html/wp-config.php"
else
    log_error "WordPress pod not found for connectivity tests"
    TESTS_FAILED=$((TESTS_FAILED + 2))
    TESTS_TOTAL=$((TESTS_TOTAL + 2))
fi

# Test 9: Ingress configuration
run_test "Ingress exists" "kubectl get ingress wordpress-ingress -n $NAMESPACE"
run_test "Ingress has correct host" "kubectl get ingress wordpress-ingress -n $NAMESPACE -o jsonpath='{.spec.rules[0].host}' | grep -q ethos.gray-beard.com"
run_test "Ingress has TLS configuration" "kubectl get ingress wordpress-ingress -n $NAMESPACE -o jsonpath='{.spec.tls[0].secretName}' | grep -q ethos-tls-secret"

# Test 10: SSL Certificate
run_test "SSL Certificate exists" "kubectl get certificate ethos-ssl-cert -n $NAMESPACE"
run_test "TLS Secret exists" "kubectl get secret ethos-tls-secret -n $NAMESPACE"

# Test 11: Port forwarding test
log_info "Testing port forwarding access..."
kubectl port-forward svc/wordpress 8080:80 -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!
sleep 5

if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q 200; then
    echo "Testing WordPress via port-forward... ✅ PASS"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "Testing WordPress via port-forward... ❌ FAIL"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Clean up port forward
kill $PF_PID 2>/dev/null || true

echo ""
echo "=============================================="
echo "📊 Test Results Summary:"
echo "Total Tests: $TESTS_TOTAL"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    log_success "🎉 All tests passed! WordPress deployment is healthy."
    
    echo ""
    log_info "🌐 Access Information:"
    echo "Local access: kubectl port-forward svc/wordpress 8080:80 -n $NAMESPACE"
    echo "Then visit: http://localhost:8080"
    echo "Production access: https://ethos.gray-beard.com"
    
    # Check SSL certificate status
    if kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" >/dev/null 2>&1; then
        local cert_status
        cert_status=$(kubectl get certificate ethos-ssl-cert -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        if [[ "$cert_status" == "True" ]]; then
            echo "SSL Certificate: ✅ Ready"
        else
            echo "SSL Certificate: ⏳ Being issued (check with: ./check-ssl-status.sh)"
        fi
    fi
    
    echo ""
    log_info "📝 Next Steps:"
    echo "1. Access WordPress and complete the setup"
    echo "2. Migrate existing content: ./migrate-wordpress-content.sh"
    echo "3. Migrate database: ./migrate-database.sh full-migration"
    echo "4. Configure SSL/TLS for production use"
    
    exit 0
else
    log_error "❌ $TESTS_FAILED test(s) failed. Please check the deployment."
    
    echo ""
    log_info "🔍 Troubleshooting Commands:"
    echo "kubectl get all -n $NAMESPACE"
    echo "kubectl describe pods -n $NAMESPACE"
    echo "kubectl logs deployment/wordpress -n $NAMESPACE"
    echo "kubectl logs deployment/mysql -n $NAMESPACE"
    echo "./monitor-wordpress.sh"
    
    exit 1
fi