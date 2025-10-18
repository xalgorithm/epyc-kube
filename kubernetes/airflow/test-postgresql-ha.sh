#!/bin/bash
set -e

# PostgreSQL High Availability Testing Script
# This script validates the PostgreSQL HA setup

echo "=== PostgreSQL High Availability Testing ==="

# Configuration
NAMESPACE="airflow"
PRIMARY_HOST="postgresql-primary"
STANDBY_HOST="postgresql-standby"
PORT="5432"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "FAILURE")
            echo -e "${RED}✗${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "INFO")
            echo -e "${NC}ℹ${NC} $message"
            ;;
    esac
}

# Function to run test and capture result
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo ""
    print_status "INFO" "Running test: $test_name"
    
    if eval "$test_command"; then
        print_status "SUCCESS" "$test_name passed"
        return 0
    else
        print_status "FAILURE" "$test_name failed"
        return 1
    fi
}

# Test 1: Check if pods are running
test_pods_running() {
    kubectl get pods -n "$NAMESPACE" | grep postgresql | grep Running | wc -l | grep -q "2"
}

# Test 2: Check primary connectivity
test_primary_connectivity() {
    kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- pg_isready -U postgres >/dev/null 2>&1
}

# Test 3: Check standby connectivity
test_standby_connectivity() {
    kubectl exec -n "$NAMESPACE" postgresql-standby-0 -- pg_isready -U postgres >/dev/null 2>&1
}

# Test 4: Verify primary is not in recovery
test_primary_role() {
    local result=$(kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
    [ "$result" = "f" ]
}

# Test 5: Verify standby is in recovery
test_standby_role() {
    local result=$(kubectl exec -n "$NAMESPACE" postgresql-standby-0 -- psql -U postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
    [ "$result" = "t" ]
}

# Test 6: Check replication connection
test_replication_connection() {
    local count=$(kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ')
    [ "$count" -gt "0" ]
}

# Test 7: Test data replication
test_data_replication() {
    local test_table="replication_test_$(date +%s)"
    local test_data="test_data_$(date +%s)"
    
    # Create test data on primary
    kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -c "CREATE TABLE $test_table (data TEXT);" >/dev/null 2>&1
    kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -c "INSERT INTO $test_table VALUES ('$test_data');" >/dev/null 2>&1
    
    # Wait for replication
    sleep 5
    
    # Check if data exists on standby
    local standby_data=$(kubectl exec -n "$NAMESPACE" postgresql-standby-0 -- psql -U postgres -t -c "SELECT data FROM $test_table;" 2>/dev/null | tr -d ' ')
    
    # Cleanup
    kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -c "DROP TABLE $test_table;" >/dev/null 2>&1
    
    [ "$standby_data" = "$test_data" ]
}

# Test 8: Check backup system
test_backup_system() {
    kubectl get cronjob postgresql-backup -n "$NAMESPACE" >/dev/null 2>&1 &&
    kubectl get pvc postgresql-backup-pvc -n "$NAMESPACE" >/dev/null 2>&1
}

# Test 9: Check monitoring system
test_monitoring_system() {
    kubectl get cronjob postgresql-health-check -n "$NAMESPACE" >/dev/null 2>&1 &&
    kubectl get configmap postgresql-monitoring-scripts -n "$NAMESPACE" >/dev/null 2>&1
}

# Test 10: Test backup script execution
test_backup_execution() {
    # Create a manual backup job
    kubectl create job --from=cronjob/postgresql-backup manual-backup-test -n "$NAMESPACE" >/dev/null 2>&1
    
    # Wait for job to complete
    sleep 30
    
    # Check if job completed successfully
    local job_status=$(kubectl get job manual-backup-test -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
    
    # Cleanup
    kubectl delete job manual-backup-test -n "$NAMESPACE" >/dev/null 2>&1
    
    [ "$job_status" = "Complete" ]
}

# Test 11: Test health check execution
test_health_check_execution() {
    # Create a manual health check job
    kubectl create job --from=cronjob/postgresql-health-check manual-health-test -n "$NAMESPACE" >/dev/null 2>&1
    
    # Wait for job to complete
    sleep 15
    
    # Check if job completed successfully
    local job_status=$(kubectl get job manual-health-test -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
    
    # Cleanup
    kubectl delete job manual-health-test -n "$NAMESPACE" >/dev/null 2>&1
    
    [ "$job_status" = "Complete" ]
}

# Test 12: Check persistent volumes
test_persistent_volumes() {
    kubectl get pvc -n "$NAMESPACE" | grep postgresql | grep Bound | wc -l | grep -q "3"  # primary, standby, backup
}

# Test 13: Test connection scripts
test_connection_scripts() {
    kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- /scripts/connection-test.sh postgresql-primary >/dev/null 2>&1
}

# Test 14: Check replication lag
test_replication_lag() {
    local lag=$(kubectl exec -n "$NAMESPACE" postgresql-standby-0 -- psql -U postgres -t -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));" 2>/dev/null | tr -d ' ')
    
    # Check if lag is reasonable (less than 60 seconds)
    if [ -n "$lag" ] && [ "$lag" != "" ]; then
        awk "BEGIN {exit !($lag < 60)}"
    else
        return 1
    fi
}

# Test 15: Test database operations
test_database_operations() {
    # Test CREATE, INSERT, SELECT, UPDATE, DELETE operations
    local test_table="ops_test_$(date +%s)"
    
    kubectl exec -n "$NAMESPACE" postgresql-primary-0 -- psql -U postgres -c "
        CREATE TABLE $test_table (id SERIAL PRIMARY KEY, name TEXT, created_at TIMESTAMP DEFAULT NOW());
        INSERT INTO $test_table (name) VALUES ('test1'), ('test2');
        UPDATE $test_table SET name = 'updated' WHERE id = 1;
        DELETE FROM $test_table WHERE id = 2;
        DROP TABLE $test_table;
    " >/dev/null 2>&1
}

# Main test execution
echo "Starting PostgreSQL High Availability tests..."
echo "Namespace: $NAMESPACE"
echo "Primary: $PRIMARY_HOST"
echo "Standby: $STANDBY_HOST"
echo ""

# Initialize counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Run all tests
tests=(
    "Pods Running:test_pods_running"
    "Primary Connectivity:test_primary_connectivity"
    "Standby Connectivity:test_standby_connectivity"
    "Primary Role:test_primary_role"
    "Standby Role:test_standby_role"
    "Replication Connection:test_replication_connection"
    "Data Replication:test_data_replication"
    "Backup System:test_backup_system"
    "Monitoring System:test_monitoring_system"
    "Backup Execution:test_backup_execution"
    "Health Check Execution:test_health_check_execution"
    "Persistent Volumes:test_persistent_volumes"
    "Connection Scripts:test_connection_scripts"
    "Replication Lag:test_replication_lag"
    "Database Operations:test_database_operations"
)

for test in "${tests[@]}"; do
    IFS=':' read -r test_name test_function <<< "$test"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if run_test "$test_name" "$test_function"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# Print summary
echo ""
echo "=== Test Summary ==="
print_status "INFO" "Total tests: $TOTAL_TESTS"
print_status "SUCCESS" "Passed: $PASSED_TESTS"
if [ $FAILED_TESTS -gt 0 ]; then
    print_status "FAILURE" "Failed: $FAILED_TESTS"
else
    print_status "SUCCESS" "Failed: $FAILED_TESTS"
fi

# Calculate success rate
SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
echo ""
if [ $SUCCESS_RATE -eq 100 ]; then
    print_status "SUCCESS" "All tests passed! PostgreSQL HA setup is working correctly."
elif [ $SUCCESS_RATE -ge 80 ]; then
    print_status "WARNING" "Most tests passed ($SUCCESS_RATE%). Some issues may need attention."
else
    print_status "FAILURE" "Many tests failed ($SUCCESS_RATE%). PostgreSQL HA setup needs investigation."
fi

echo ""
echo "=== Additional Information ==="
echo "To view detailed status:"
echo "  kubectl get all -n $NAMESPACE"
echo ""
echo "To check replication status:"
echo "  kubectl exec -n $NAMESPACE postgresql-primary-0 -- psql -U postgres -c 'SELECT * FROM pg_stat_replication;'"
echo ""
echo "To view logs:"
echo "  kubectl logs -n $NAMESPACE postgresql-primary-0"
echo "  kubectl logs -n $NAMESPACE postgresql-standby-0"
echo ""

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
else
    exit 1
fi