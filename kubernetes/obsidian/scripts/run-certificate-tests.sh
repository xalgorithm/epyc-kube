#!/bin/bash

# Master Certificate Test Runner
# Orchestrates all certificate functionality tests for Obsidian stack
# Requirements: 1.1, 1.2, 1.4, 2.1, 2.2, 2.4, 3.4, 4.1, 4.2

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBSIDIAN_DIR="$(dirname "$SCRIPT_DIR")"
TEST_RESULTS_DIR="${SCRIPT_DIR}/test-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MASTER_LOG_FILE="${TEST_RESULTS_DIR}/master-test-log-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test suite configuration
declare -A TEST_SUITES=(
    ["functionality"]="test-certificate-functionality.sh"
    ["renewal"]="test-certificate-renewal.sh"
    ["error-handling"]="test-certificate-error-handling.sh"
    ["https-connectivity"]="test-https-connectivity.sh"
)

# Test results tracking
declare -A SUITE_RESULTS=()
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$MASTER_LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$MASTER_LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$MASTER_LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$MASTER_LOG_FILE"
}

log_header() {
    echo -e "${BOLD}${CYAN}$1${NC}" | tee -a "$MASTER_LOG_FILE"
}

# Function to setup test environment
setup_test_environment() {
    log_info "Setting up master test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Initialize master log file
    {
        echo "Certificate Test Suite Master Runner"
        echo "===================================="
        echo "Start Time: $(date)"
        echo "Script Directory: $SCRIPT_DIR"
        echo "Obsidian Directory: $OBSIDIAN_DIR"
        echo "Results Directory: $TEST_RESULTS_DIR"
        echo
    } > "$MASTER_LOG_FILE"
    
    log_success "Master test environment setup complete"
}

# Function to check if test scripts exist
check_test_scripts() {
    log_info "Checking test script availability..."
    
    local missing_scripts=()
    
    for suite_name in "${!TEST_SUITES[@]}"; do
        local script_name="${TEST_SUITES[$suite_name]}"
        local script_path="${SCRIPT_DIR}/${script_name}"
        
        if [ ! -f "$script_path" ]; then
            missing_scripts+=("$script_name")
        elif [ ! -x "$script_path" ]; then
            log_warning "Making $script_name executable..."
            chmod +x "$script_path"
        fi
    done
    
    if [ ${#missing_scripts[@]} -ne 0 ]; then
        log_error "Missing test scripts: ${missing_scripts[*]}"
        exit 1
    fi
    
    log_success "All test scripts are available"
}

# Function to run a test suite
run_test_suite() {
    local suite_name="$1"
    local script_name="${TEST_SUITES[$suite_name]}"
    local script_path="${SCRIPT_DIR}/${script_name}"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    log_header "Running $suite_name test suite ($script_name)"
    echo
    
    local suite_log_file="${TEST_RESULTS_DIR}/${suite_name}-${TIMESTAMP}.log"
    local start_time=$(date +%s)
    
    # Run the test suite and capture output
    if bash "$script_path" 2>&1 | tee "$suite_log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        SUITE_RESULTS[$suite_name]="PASSED"
        PASSED_SUITES=$((PASSED_SUITES + 1))
        
        log_success "$suite_name test suite PASSED (duration: ${duration}s)"
        echo "Suite log: $suite_log_file" >> "$MASTER_LOG_FILE"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        SUITE_RESULTS[$suite_name]="FAILED"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        
        log_error "$suite_name test suite FAILED (duration: ${duration}s)"
        echo "Suite log: $suite_log_file" >> "$MASTER_LOG_FILE"
    fi
    
    echo
}

# Function to generate comprehensive test report
generate_master_report() {
    local report_file="${TEST_RESULTS_DIR}/master-test-report-${TIMESTAMP}.html"
    local summary_file="${TEST_RESULTS_DIR}/test-summary-${TIMESTAMP}.txt"
    
    # Generate text summary
    {
        echo "Certificate Test Suite - Master Report"
        echo "======================================"
        echo "Date: $(date)"
        echo "Total Test Suites: $TOTAL_SUITES"
        echo "Passed Suites: $PASSED_SUITES"
        echo "Failed Suites: $FAILED_SUITES"
        echo "Success Rate: $(( PASSED_SUITES * 100 / TOTAL_SUITES ))%"
        echo
        echo "Suite Results:"
        echo "=============="
        
        for suite_name in "${!SUITE_RESULTS[@]}"; do
            local result="${SUITE_RESULTS[$suite_name]}"
            echo "- $suite_name: $result"
        done
        
        echo
        echo "Detailed Logs:"
        echo "=============="
        echo "Master Log: $MASTER_LOG_FILE"
        
        for suite_name in "${!TEST_SUITES[@]}"; do
            local suite_log="${TEST_RESULTS_DIR}/${suite_name}-${TIMESTAMP}.log"
            if [ -f "$suite_log" ]; then
                echo "- $suite_name: $suite_log"
            fi
        done
        
        echo
        if [ $FAILED_SUITES -gt 0 ]; then
            echo "OVERALL RESULT: FAILED"
            echo
            echo "Some test suites failed. Please review the detailed logs for more information."
            echo
            echo "Common troubleshooting steps:"
            echo "1. Ensure cert-manager is properly installed and configured"
            echo "2. Verify ClusterIssuer resources are ready"
            echo "3. Check DNS resolution for test domains"
            echo "4. Review ingress controller configuration"
            echo "5. Check network connectivity to Let's Encrypt servers"
            echo "6. Verify Kubernetes cluster has sufficient resources"
        else
            echo "OVERALL RESULT: PASSED"
            echo
            echo "All certificate functionality tests passed successfully!"
            echo "The Obsidian stack SSL certificate configuration is working correctly."
        fi
    } > "$summary_file"
    
    # Generate HTML report
    {
        cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Certificate Test Suite Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; margin-bottom: 20px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .metric { background-color: #f8f9fa; padding: 15px; border-radius: 5px; text-align: center; border-left: 4px solid #007acc; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007acc; }
        .metric-label { color: #666; margin-top: 5px; }
        .suite-results { margin-bottom: 30px; }
        .suite { margin-bottom: 15px; padding: 15px; border-radius: 5px; }
        .suite.passed { background-color: #d4edda; border-left: 4px solid #28a745; }
        .suite.failed { background-color: #f8d7da; border-left: 4px solid #dc3545; }
        .suite-name { font-weight: bold; font-size: 1.1em; }
        .suite-status { float: right; padding: 2px 8px; border-radius: 3px; color: white; font-size: 0.9em; }
        .status-passed { background-color: #28a745; }
        .status-failed { background-color: #dc3545; }
        .logs-section { background-color: #f8f9fa; padding: 15px; border-radius: 5px; }
        .log-link { display: block; margin: 5px 0; color: #007acc; text-decoration: none; }
        .log-link:hover { text-decoration: underline; }
        .footer { text-align: center; margin-top: 30px; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Certificate Test Suite Report</h1>
            <p>Generated on $(date)</p>
        </div>
        
        <div class="summary">
            <div class="metric">
                <div class="metric-value">$TOTAL_SUITES</div>
                <div class="metric-label">Total Suites</div>
            </div>
            <div class="metric">
                <div class="metric-value">$PASSED_SUITES</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric">
                <div class="metric-value">$FAILED_SUITES</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric">
                <div class="metric-value">$(( PASSED_SUITES * 100 / TOTAL_SUITES ))%</div>
                <div class="metric-label">Success Rate</div>
            </div>
        </div>
        
        <div class="suite-results">
            <h2>Test Suite Results</h2>
EOF
        
        for suite_name in "${!SUITE_RESULTS[@]}"; do
            local result="${SUITE_RESULTS[$suite_name]}"
            local css_class=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            local status_class="status-$(echo "$result" | tr '[:upper:]' '[:lower:]')"
            
            cat << EOF
            <div class="suite $css_class">
                <div class="suite-name">$suite_name
                    <span class="suite-status $status_class">$result</span>
                </div>
                <div>Test Script: ${TEST_SUITES[$suite_name]}</div>
            </div>
EOF
        done
        
        cat << EOF
        </div>
        
        <div class="logs-section">
            <h2>Detailed Logs</h2>
            <a href="file://$MASTER_LOG_FILE" class="log-link">Master Log</a>
EOF
        
        for suite_name in "${!TEST_SUITES[@]}"; do
            local suite_log="${TEST_RESULTS_DIR}/${suite_name}-${TIMESTAMP}.log"
            if [ -f "$suite_log" ]; then
                echo "            <a href=\"file://$suite_log\" class=\"log-link\">$suite_name Log</a>"
            fi
        done
        
        cat << 'EOF'
        </div>
        
        <div class="footer">
            <p>Certificate Test Suite for Obsidian Stack</p>
        </div>
    </div>
</body>
</html>
EOF
    } > "$report_file"
    
    # Display summary
    cat "$summary_file"
    
    log_info "Test reports generated:"
    log_info "- Summary: $summary_file"
    log_info "- HTML Report: $report_file"
    log_info "- Master Log: $MASTER_LOG_FILE"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options] [test-suites...]"
    echo
    echo "Master Certificate Test Runner"
    echo
    echo "Available Test Suites:"
    for suite_name in "${!TEST_SUITES[@]}"; do
        echo "  $suite_name - ${TEST_SUITES[$suite_name]}"
    done
    echo
    echo "Options:"
    echo "  --all                  Run all test suites (default)"
    echo "  --quick                Run only basic functionality and connectivity tests"
    echo "  --staging-only         Run tests in staging environment only"
    echo "  --skip-renewal         Skip certificate renewal tests"
    echo "  --skip-error-handling  Skip error handling tests"
    echo "  --parallel             Run test suites in parallel (experimental)"
    echo "  --help                 Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                    # Run all test suites"
    echo "  $0 --quick                           # Run quick test suite"
    echo "  $0 functionality https-connectivity  # Run specific test suites"
    echo "  $0 --skip-renewal --skip-error-handling  # Skip specific test types"
    echo
}

# Parse command line arguments
RUN_ALL=true
QUICK_MODE=false
STAGING_ONLY=false
SKIP_RENEWAL=false
SKIP_ERROR_HANDLING=false
PARALLEL_MODE=false
SELECTED_SUITES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            RUN_ALL=true
            shift
            ;;
        --quick)
            QUICK_MODE=true
            RUN_ALL=false
            shift
            ;;
        --staging-only)
            STAGING_ONLY=true
            shift
            ;;
        --skip-renewal)
            SKIP_RENEWAL=true
            shift
            ;;
        --skip-error-handling)
            SKIP_ERROR_HANDLING=true
            shift
            ;;
        --parallel)
            PARALLEL_MODE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        functionality|renewal|error-handling|https-connectivity)
            SELECTED_SUITES+=("$1")
            RUN_ALL=false
            shift
            ;;
        *)
            log_error "Unknown option or test suite: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Determine which test suites to run
SUITES_TO_RUN=()

if [ "$RUN_ALL" = true ]; then
    for suite_name in "${!TEST_SUITES[@]}"; do
        SUITES_TO_RUN+=("$suite_name")
    done
elif [ "$QUICK_MODE" = true ]; then
    SUITES_TO_RUN=("functionality" "https-connectivity")
elif [ ${#SELECTED_SUITES[@]} -gt 0 ]; then
    SUITES_TO_RUN=("${SELECTED_SUITES[@]}")
else
    log_error "No test suites specified"
    show_usage
    exit 1
fi

# Apply filters
if [ "$SKIP_RENEWAL" = true ]; then
    SUITES_TO_RUN=($(printf '%s\n' "${SUITES_TO_RUN[@]}" | grep -v "renewal"))
fi

if [ "$SKIP_ERROR_HANDLING" = true ]; then
    SUITES_TO_RUN=($(printf '%s\n' "${SUITES_TO_RUN[@]}" | grep -v "error-handling"))
fi

# Main execution
main() {
    log_header "Certificate Test Suite Master Runner"
    echo
    
    setup_test_environment
    check_test_scripts
    
    echo
    log_info "Test suites to run: ${SUITES_TO_RUN[*]}"
    
    if [ "$STAGING_ONLY" = true ]; then
        log_info "Running in staging-only mode"
    fi
    
    if [ "$PARALLEL_MODE" = true ]; then
        log_warning "Parallel mode is experimental and may cause resource conflicts"
    fi
    
    echo
    log_header "Starting Test Execution"
    echo
    
    local start_time=$(date +%s)
    
    # Run test suites
    if [ "$PARALLEL_MODE" = true ]; then
        # Parallel execution (experimental)
        local pids=()
        
        for suite_name in "${SUITES_TO_RUN[@]}"; do
            run_test_suite "$suite_name" &
            pids+=($!)
        done
        
        # Wait for all test suites to complete
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
    else
        # Sequential execution (default)
        for suite_name in "${SUITES_TO_RUN[@]}"; do
            run_test_suite "$suite_name"
        done
    fi
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    echo
    log_header "Test Execution Complete"
    echo
    
    log_info "Total execution time: ${total_duration}s"
    
    # Generate comprehensive report
    generate_master_report
    
    # Exit with appropriate code
    if [ $FAILED_SUITES -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"