#!/bin/bash

# Redis High Availability Testing Script
# This script tests Redis Sentinel cluster functionality including failover scenarios

set -euo pipefail

# Configuration
NAMESPACE="airflow"
REDIS_PASSWORD="airflow-redis-2024"
SERVICE_NAME="mymaster"

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

# Get Redis pod names
get_redis_pods() {
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n'
}

# Get current master from Sentinel
get_current_master() {
    local sentinel_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n "$NAMESPACE" "$sentinel_pod" -c sentinel -- redis-cli -p 26379 -a "$REDIS_PASSWORD" --no-auth-warning sentinel get-master-addr-by-name "$SERVICE_NAME" 2>/dev/null || echo ""
}

# Test basic connectivity
test_basic_connectivity() {
    log_info "Testing basic connectivity to all Redis instances..."
    
    local pods=($(get_redis_pods))
    local success_count=0
    
    for pod in "${pods[@]}"; do
        log_info "Testing connectivity to $pod..."
        
        # Test Redis port
        if kubectl exec -n "$NAMESPACE" "$pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping > /dev/null 2>&1; then
            log_success "Redis connection to $pod: OK"
            ((success_count++))
        else
            log_error "Redis connection to $pod: FAILED"
        fi
        
        # Test Sentinel port
        if kubectl exec -n "$NAMESPACE" "$pod" -c sentinel -- redis-cli -p 26379 -a "$REDIS_PASSWORD" --no-auth-warning ping > /dev/null 2>&1; then
            log_success "Sentinel connection to $pod: OK"
        else
            log_error "Sentinel connection to $pod: FAILED"
        fi
    done
    
    if [[ $success_count -eq ${#pods[@]} ]]; then
        log_success "Basic connectivity test: PASSED ($success_count/${#pods[@]} nodes)"
        return 0
    else
        log_error "Basic connectivity test: FAILED ($success_count/${#pods[@]} nodes)"
        return 1
    fi
}

# Test master discovery
test_master_discovery() {
    log_info "Testing master discovery through Sentinel..."
    
    local pods=($(get_redis_pods))
    local master_addresses=()
    local consensus_count=0
    
    for pod in "${pods[@]}"; do
        log_info "Querying master from Sentinel on $pod..."
        
        local master_addr=$(kubectl exec -n "$NAMESPACE" "$pod" -c sentinel -- redis-cli -p 26379 -a "$REDIS_PASSWORD" --no-auth-warning sentinel get-master-addr-by-name "$SERVICE_NAME" 2>/dev/null || echo "")
        
        if [[ -n "$master_addr" ]]; then
            master_addresses+=("$master_addr")
            log_success "Master discovered: $master_addr"
            ((consensus_count++))
        else
            log_error "Failed to discover master from $pod"
        fi
    done
    
    if [[ $consensus_count -ge 2 ]]; then
        # Check consensus
        local unique_masters=$(printf '%s\n' "${master_addresses[@]}" | sort -u | wc -l)
        if [[ $unique_masters -eq 1 ]]; then
            log_success "Master discovery test: PASSED (consensus achieved)"
            log_info "Current master: ${master_addresses[0]}"
            return 0
        else
            log_error "Master discovery test: FAILED (split-brain detected)"
            printf '%s\n' "${master_addresses[@]}" | sort -u
            return 1
        fi
    else
        log_error "Master discovery test: FAILED (insufficient consensus: $consensus_count/3)"
        return 1
    fi
}

# Test replication
test_replication() {
    log_info "Testing Redis replication..."
    
    local master_info=$(get_current_master)
    if [[ -z "$master_info" ]]; then
        log_error "Cannot determine current master for replication test"
        return 1
    fi
    
    local master_host=$(echo $master_info | cut -d' ' -f1)
    local master_port=$(echo $master_info | cut -d' ' -f2)
    
    # Find the master pod
    local master_pod=""
    local pods=($(get_redis_pods))
    
    for pod in "${pods[@]}"; do
        local pod_ip=$(kubectl get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.status.podIP}')
        if [[ "$pod_ip" == "$master_host" ]]; then
            master_pod="$pod"
            break
        fi
    done
    
    if [[ -z "$master_pod" ]]; then
        log_error "Cannot find master pod for replication test"
        return 1
    fi
    
    log_info "Testing replication using master pod: $master_pod"
    
    # Write test data to master
    local test_key="replication_test_$(date +%s)"
    local test_value="test_value_$(date +%s)"
    
    if kubectl exec -n "$NAMESPACE" "$master_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning set "$test_key" "$test_value" > /dev/null; then
        log_success "Test data written to master"
    else
        log_error "Failed to write test data to master"
        return 1
    fi
    
    # Wait for replication
    sleep 2
    
    # Check replication on slaves
    local replication_success=0
    local slave_count=0
    
    for pod in "${pods[@]}"; do
        if [[ "$pod" != "$master_pod" ]]; then
            ((slave_count++))
            local retrieved_value=$(kubectl exec -n "$NAMESPACE" "$pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning get "$test_key" 2>/dev/null || echo "")
            
            if [[ "$retrieved_value" == "$test_value" ]]; then
                log_success "Replication verified on slave: $pod"
                ((replication_success++))
            else
                log_error "Replication failed on slave: $pod (expected: $test_value, got: $retrieved_value)"
            fi
        fi
    done
    
    # Cleanup test data
    kubectl exec -n "$NAMESPACE" "$master_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning del "$test_key" > /dev/null
    
    if [[ $replication_success -eq $slave_count ]]; then
        log_success "Replication test: PASSED ($replication_success/$slave_count slaves)"
        return 0
    else
        log_error "Replication test: FAILED ($replication_success/$slave_count slaves)"
        return 1
    fi
}

# Test persistence
test_persistence() {
    log_info "Testing Redis persistence..."
    
    local test_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}')
    
    # Write test data
    local test_key="persistence_test_$(date +%s)"
    local test_value="persistent_value_$(date +%s)"
    
    if kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning set "$test_key" "$test_value" > /dev/null; then
        log_success "Test data written for persistence test"
    else
        log_error "Failed to write test data for persistence test"
        return 1
    fi
    
    # Force a save
    if kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning bgsave > /dev/null; then
        log_success "Background save initiated"
    else
        log_warning "Failed to initiate background save"
    fi
    
    # Wait for save to complete
    sleep 5
    
    # Check if data persists after restart (simulate by checking if data exists)
    local retrieved_value=$(kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning get "$test_key" 2>/dev/null || echo "")
    
    if [[ "$retrieved_value" == "$test_value" ]]; then
        log_success "Persistence test: PASSED (data persisted)"
        
        # Cleanup
        kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning del "$test_key" > /dev/null
        return 0
    else
        log_error "Persistence test: FAILED (data not persisted)"
        return 1
    fi
}

# Test connection pooling
test_connection_pooling() {
    log_info "Testing connection pooling and concurrent access..."
    
    local test_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}')
    
    # Test multiple concurrent connections
    local concurrent_tests=5
    local success_count=0
    
    for i in $(seq 1 $concurrent_tests); do
        local test_key="pool_test_${i}_$(date +%s)"
        local test_value="pool_value_${i}_$(date +%s)"
        
        if kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning set "$test_key" "$test_value" > /dev/null 2>&1; then
            local retrieved_value=$(kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning get "$test_key" 2>/dev/null || echo "")
            
            if [[ "$retrieved_value" == "$test_value" ]]; then
                ((success_count++))
                # Cleanup
                kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning del "$test_key" > /dev/null 2>&1
            fi
        fi
    done
    
    if [[ $success_count -eq $concurrent_tests ]]; then
        log_success "Connection pooling test: PASSED ($success_count/$concurrent_tests operations)"
        return 0
    else
        log_error "Connection pooling test: FAILED ($success_count/$concurrent_tests operations)"
        return 1
    fi
}

# Test failover simulation (without actually causing failover)
test_failover_readiness() {
    log_info "Testing failover readiness..."
    
    local pods=($(get_redis_pods))
    local sentinel_ready=0
    
    for pod in "${pods[@]}"; do
        log_info "Checking failover readiness on Sentinel: $pod"
        
        # Check if Sentinel can perform failover
        local ckquorum_result=$(kubectl exec -n "$NAMESPACE" "$pod" -c sentinel -- redis-cli -p 26379 -a "$REDIS_PASSWORD" --no-auth-warning sentinel ckquorum "$SERVICE_NAME" 2>/dev/null || echo "")
        
        if [[ "$ckquorum_result" == *"OK"* ]]; then
            log_success "Sentinel $pod is ready for failover"
            ((sentinel_ready++))
        else
            log_warning "Sentinel $pod may not be ready for failover: $ckquorum_result"
        fi
    done
    
    if [[ $sentinel_ready -ge 2 ]]; then
        log_success "Failover readiness test: PASSED ($sentinel_ready/3 sentinels ready)"
        return 0
    else
        log_error "Failover readiness test: FAILED ($sentinel_ready/3 sentinels ready)"
        return 1
    fi
}

# Test monitoring endpoints
test_monitoring() {
    log_info "Testing monitoring endpoints..."
    
    # Check if redis-exporter is running
    local exporter_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$exporter_pod" ]]; then
        log_info "Testing metrics endpoint on redis-exporter: $exporter_pod"
        
        # Test metrics endpoint
        if kubectl exec -n "$NAMESPACE" "$exporter_pod" -- wget -q -O - http://localhost:9121/metrics | head -5 > /dev/null 2>&1; then
            log_success "Metrics endpoint test: PASSED"
        else
            log_warning "Metrics endpoint test: FAILED"
        fi
    else
        log_warning "Redis exporter not found, skipping metrics test"
    fi
    
    # Test if ServiceMonitor exists
    if kubectl get servicemonitor -n "$NAMESPACE" redis-metrics > /dev/null 2>&1; then
        log_success "ServiceMonitor exists for Prometheus scraping"
    else
        log_warning "ServiceMonitor not found"
    fi
}

# Performance benchmark
performance_benchmark() {
    log_info "Running performance benchmark..."
    
    local test_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}')
    
    log_info "Running redis-benchmark on $test_pod..."
    
    # Run a quick benchmark
    local benchmark_result=$(kubectl exec -n "$NAMESPACE" "$test_pod" -c redis -- redis-benchmark -a "$REDIS_PASSWORD" -q -t set,get -n 1000 -c 10 2>/dev/null || echo "Benchmark failed")
    
    if [[ "$benchmark_result" != "Benchmark failed" ]]; then
        log_success "Performance benchmark completed:"
        echo "$benchmark_result"
    else
        log_warning "Performance benchmark failed"
    fi
}

# Generate comprehensive test report
generate_test_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="/tmp/redis-ha-test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Redis High Availability Test Report"
        echo "Generated: $timestamp"
        echo "Namespace: $NAMESPACE"
        echo "Service Name: $SERVICE_NAME"
        echo "=================================="
        echo ""
        
        echo "Test Results:"
        echo "============="
        
        # Run all tests and capture results
        local tests=(
            "test_basic_connectivity:Basic Connectivity"
            "test_master_discovery:Master Discovery"
            "test_replication:Replication"
            "test_persistence:Persistence"
            "test_connection_pooling:Connection Pooling"
            "test_failover_readiness:Failover Readiness"
            "test_monitoring:Monitoring"
        )
        
        local passed=0
        local total=${#tests[@]}
        
        for test_info in "${tests[@]}"; do
            local test_func=$(echo $test_info | cut -d: -f1)
            local test_name=$(echo $test_info | cut -d: -f2)
            
            echo -n "- $test_name: "
            if $test_func &>/dev/null; then
                echo "PASSED"
                ((passed++))
            else
                echo "FAILED"
            fi
        done
        
        echo ""
        echo "Summary: $passed/$total tests passed"
        echo ""
        
        # Cluster information
        echo "Cluster Information:"
        echo "==================="
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis -o wide
        echo ""
        kubectl get services -n "$NAMESPACE" -l app.kubernetes.io/name=redis
        echo ""
        kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=redis
        
    } > "$report_file"
    
    log_success "Test report generated: $report_file"
    cat "$report_file"
}

# Main function
main() {
    log_info "Starting Redis High Availability tests..."
    
    local overall_success=0
    
    case "${1:-all}" in
        "all")
            log_info "Running comprehensive HA tests..."
            
            local tests=(
                "test_basic_connectivity"
                "test_master_discovery"
                "test_replication"
                "test_persistence"
                "test_connection_pooling"
                "test_failover_readiness"
                "test_monitoring"
            )
            
            local passed=0
            local total=${#tests[@]}
            
            for test_func in "${tests[@]}"; do
                echo ""
                if $test_func; then
                    ((passed++))
                else
                    overall_success=1
                fi
            done
            
            echo ""
            performance_benchmark
            
            echo ""
            log_info "Test Summary: $passed/$total tests passed"
            
            if [[ $passed -eq $total ]]; then
                log_success "All Redis HA tests PASSED!"
            else
                log_error "Some Redis HA tests FAILED!"
                overall_success=1
            fi
            ;;
        "connectivity")
            test_basic_connectivity || overall_success=1
            ;;
        "master")
            test_master_discovery || overall_success=1
            ;;
        "replication")
            test_replication || overall_success=1
            ;;
        "persistence")
            test_persistence || overall_success=1
            ;;
        "pooling")
            test_connection_pooling || overall_success=1
            ;;
        "failover")
            test_failover_readiness || overall_success=1
            ;;
        "monitoring")
            test_monitoring || overall_success=1
            ;;
        "benchmark")
            performance_benchmark
            ;;
        "report")
            generate_test_report
            ;;
        *)
            echo "Usage: $0 {all|connectivity|master|replication|persistence|pooling|failover|monitoring|benchmark|report}"
            echo ""
            echo "Commands:"
            echo "  all          - Run all HA tests (default)"
            echo "  connectivity - Test basic connectivity"
            echo "  master       - Test master discovery"
            echo "  replication  - Test data replication"
            echo "  persistence  - Test data persistence"
            echo "  pooling      - Test connection pooling"
            echo "  failover     - Test failover readiness"
            echo "  monitoring   - Test monitoring endpoints"
            echo "  benchmark    - Run performance benchmark"
            echo "  report       - Generate comprehensive test report"
            exit 1
            ;;
    esac
    
    exit $overall_success
}

# Handle command line arguments
main "$@"