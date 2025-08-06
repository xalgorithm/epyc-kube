# Certificate Functionality Test Suite

This directory contains comprehensive automated tests for SSL certificate functionality in the Obsidian stack. The test suite validates certificate provisioning, renewal, error handling, and HTTPS connectivity.

## Directory Structure

```
kubernetes/obsidian/
├── scripts/                           # All shell scripts
│   ├── run-certificate-tests.sh       # Master test runner
│   ├── test-certificate-functionality.sh
│   ├── test-certificate-renewal.sh
│   ├── test-certificate-error-handling.sh
│   ├── test-https-connectivity.sh
│   ├── validate-ssl-certificates.sh
│   ├── certificate-expiry-check.sh
│   ├── switch-certificates.sh
│   └── deploy-monitoring.sh
├── README-certificate-tests.md        # This file
└── [YAML configuration files]
```

## Test Scripts

### 1. Master Test Runner
- **File**: `scripts/run-certificate-tests.sh`
- **Purpose**: Orchestrates all certificate tests and generates comprehensive reports
- **Usage**: `./scripts/run-certificate-tests.sh [options] [test-suites...]`

### 2. Certificate Functionality Tests
- **File**: `scripts/test-certificate-functionality.sh`
- **Purpose**: Tests certificate provisioning, validation, and basic functionality
- **Usage**: `./scripts/test-certificate-functionality.sh [options]`

### 3. Certificate Renewal Tests
- **File**: `scripts/test-certificate-renewal.sh`
- **Purpose**: Tests certificate renewal scenarios and auto-renewal behavior
- **Usage**: `./scripts/test-certificate-renewal.sh [options]`

### 4. Error Handling Tests
- **File**: `scripts/test-certificate-error-handling.sh`
- **Purpose**: Tests various error scenarios and proper error handling
- **Usage**: `./scripts/test-certificate-error-handling.sh [options]`

### 5. HTTPS Connectivity Tests
- **File**: `scripts/test-https-connectivity.sh`
- **Purpose**: Tests HTTPS connectivity and certificate validation for both services
- **Usage**: `./scripts/test-https-connectivity.sh [options]`

## Utility Scripts

### 6. SSL Certificate Validation
- **File**: `scripts/validate-ssl-certificates.sh`
- **Purpose**: Validates SSL certificates for both Obsidian and CouchDB services
- **Usage**: `./scripts/validate-ssl-certificates.sh [options]`

### 7. Certificate Expiry Check
- **File**: `scripts/certificate-expiry-check.sh`
- **Purpose**: Monitors certificate expiration dates and sends alerts
- **Usage**: `./scripts/certificate-expiry-check.sh [options]`

### 8. Certificate Environment Switcher
- **File**: `scripts/switch-certificates.sh`
- **Purpose**: Switches between staging and production SSL certificates
- **Usage**: `./scripts/switch-certificates.sh [staging|production] [options]`

### 9. Monitoring Deployment
- **File**: `scripts/deploy-monitoring.sh`
- **Purpose**: Deploys monitoring components for Obsidian and CouchDB
- **Usage**: `./scripts/deploy-monitoring.sh`

## Quick Start

### Run All Tests
```bash
./scripts/run-certificate-tests.sh
```

### Run Quick Test Suite
```bash
./scripts/run-certificate-tests.sh --quick
```

### Run Specific Test Suites
```bash
./scripts/run-certificate-tests.sh functionality https-connectivity
```

### Run Tests in Staging Only
```bash
./scripts/run-certificate-tests.sh --staging-only
```

## Test Requirements

### Prerequisites
- `kubectl` - Kubernetes command-line tool
- `openssl` - SSL/TLS toolkit
- `curl` - HTTP client
- `jq` - JSON processor
- `dig` or `nslookup` - DNS lookup tools

### Kubernetes Requirements
- cert-manager installed and running
- ClusterIssuer resources configured (letsencrypt-staging, letsencrypt-prod)
- Obsidian namespace exists
- Traefik ingress controller running

### Network Requirements
- DNS resolution for test domains
- Internet connectivity to Let's Encrypt servers
- Access to Kubernetes cluster

## Test Coverage

### Certificate Provisioning (Requirements: 1.1, 1.3, 2.1, 2.3, 3.1, 3.2, 4.1, 4.2)
- ✅ ClusterIssuer availability validation
- ✅ Staging certificate provisioning
- ✅ Production certificate provisioning
- ✅ Certificate secret creation
- ✅ Environment switching

### Certificate Renewal (Requirements: 1.2, 2.2, 3.4)
- ✅ Manual renewal by certificate deletion
- ✅ Manual renewal by secret deletion
- ✅ Auto-renewal configuration validation
- ✅ Near-expiry simulation

### Error Handling (Requirements: 1.4, 2.4, 3.4, 4.1, 4.2)
- ✅ Invalid ClusterIssuer handling
- ✅ Invalid domain name handling
- ✅ Missing service backend handling
- ✅ Rate limiting simulation
- ✅ Certificate validation failure handling
- ✅ Network connectivity error handling

### HTTPS Connectivity (Requirements: 1.1, 1.4, 2.1, 2.4, 3.4)
- ✅ DNS resolution testing
- ✅ Basic HTTPS connectivity
- ✅ Certificate verification
- ✅ Certificate details validation
- ✅ HTTP to HTTPS redirect testing
- ✅ TLS configuration validation
- ✅ Service-specific endpoint testing
- ✅ Concurrent connection testing

## Test Results

### Output Locations
- **Test Results Directory**: `./scripts/test-results/`
- **Master Log**: `scripts/test-results/master-test-log-TIMESTAMP.log`
- **Individual Suite Logs**: `scripts/test-results/SUITE-NAME-TIMESTAMP.log`
- **Summary Report**: `scripts/test-results/test-summary-TIMESTAMP.txt`
- **HTML Report**: `scripts/test-results/master-test-report-TIMESTAMP.html`

### Exit Codes
- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Script error or invalid arguments

## Common Test Scenarios

### Initial Certificate Setup Testing
```bash
# Test certificate provisioning in staging
./scripts/test-certificate-functionality.sh --skip-connectivity

# Test HTTPS connectivity after provisioning
./scripts/test-https-connectivity.sh
```

### Certificate Renewal Testing
```bash
# Test renewal scenarios
./scripts/test-certificate-renewal.sh

# Test renewal with specific timeout
./scripts/test-certificate-renewal.sh --timeout 600
```

### Error Handling Validation
```bash
# Test error handling scenarios
./scripts/test-certificate-error-handling.sh

# Skip rate limiting tests (to avoid potential issues)
./scripts/test-certificate-error-handling.sh --skip-rate-limit
```

### Production Readiness Testing
```bash
# Run comprehensive test suite
./scripts/run-certificate-tests.sh --all

# Generate detailed reports
ls -la scripts/test-results/
```

## Troubleshooting

### Common Issues

#### Certificate Provisioning Failures
- **Symptom**: Certificates fail to be issued
- **Check**: ClusterIssuer status, DNS resolution, ingress controller logs
- **Solution**: Verify cert-manager configuration and network connectivity

#### HTTPS Connectivity Issues
- **Symptom**: HTTPS connections fail or show certificate errors
- **Check**: Certificate validity, DNS resolution, firewall rules
- **Solution**: Verify certificate installation and network configuration

#### Test Script Failures
- **Symptom**: Test scripts exit with errors
- **Check**: Prerequisites, Kubernetes connectivity, permissions
- **Solution**: Install missing tools, verify cluster access

### Debug Commands
```bash
# Check cert-manager status
kubectl get pods -n cert-manager

# Check ClusterIssuer status
kubectl get clusterissuer

# Check certificate status
kubectl get certificates -n obsidian

# Check certificate details
kubectl describe certificate obsidian-tls -n obsidian

# Check ingress status
kubectl get ingress -n obsidian

# View cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

## Integration with CI/CD

### GitHub Actions Example
```yaml
- name: Run Certificate Tests
  run: |
    cd kubernetes/obsidian
    ./scripts/run-certificate-tests.sh --quick
    
- name: Upload Test Results
  uses: actions/upload-artifact@v3
  if: always()
  with:
    name: certificate-test-results
    path: kubernetes/obsidian/scripts/test-results/
```

### Jenkins Pipeline Example
```groovy
stage('Certificate Tests') {
    steps {
        dir('kubernetes/obsidian') {
            sh './scripts/run-certificate-tests.sh --all'
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'kubernetes/obsidian/scripts/test-results/**/*'
        }
    }
}
```

## Contributing

When adding new certificate tests:

1. Follow the existing test script patterns
2. Use the logging functions for consistent output
3. Include proper error handling and cleanup
4. Update this README with new test descriptions
5. Ensure tests are idempotent and can run multiple times

## Requirements Mapping

This test suite addresses the following requirements from the specification:

- **1.1**: Obsidian SSL certificate validation
- **1.2**: Automatic certificate renewal for Obsidian
- **1.4**: Error handling for Obsidian certificate failures
- **2.1**: CouchDB SSL certificate validation
- **2.2**: Automatic certificate renewal for CouchDB
- **2.4**: Error handling for CouchDB certificate failures
- **3.1**: Consistent cert-manager configuration
- **3.2**: Proper cert-manager annotations
- **3.4**: Certificate validation and monitoring
- **4.1**: Staging environment support
- **4.2**: Production environment support