# SSL Certificate Validation Script

This directory contains a script to validate SSL certificates for the Obsidian stack services.

> **Note**: For comprehensive SSL certificate management procedures, including switching between environments, troubleshooting, and maintenance, see the main [README.md](README.md) file.

## Overview

The `validate-ssl-certificates.sh` script provides comprehensive SSL certificate validation for:
- Obsidian application (blackrock.gray-beard.com)
- CouchDB database (couchdb.blackrock.gray-beard.com)

## Features

- **HTTPS Connectivity Testing**: Verifies that services are accessible over HTTPS
- **Certificate Validation**: Checks certificate validity, expiration, and issuer information
- **Kubernetes Secret Verification**: Validates certificates stored in Kubernetes secrets
- **cert-manager Integration**: Checks Certificate resource status
- **Cross-platform Compatibility**: Works on both Linux and macOS
- **Detailed Error Reporting**: Provides informative output for troubleshooting

## Prerequisites

The script requires the following tools to be installed:
- `openssl` - For certificate analysis
- `curl` - For HTTPS connectivity testing
- `kubectl` - For Kubernetes resource inspection
- `jq` - For JSON parsing (optional, used for cert-manager resources)

## Usage

### Basic Usage

```bash
# Validate all certificates
./validate-ssl-certificates.sh

# Show help
./validate-ssl-certificates.sh --help

# Validate only Obsidian certificates
./validate-ssl-certificates.sh --obsidian

# Validate only CouchDB certificates
./validate-ssl-certificates.sh --couchdb
```

### Command Line Options

- `-h, --help`: Show help message
- `-o, --obsidian`: Validate only Obsidian certificates
- `-c, --couchdb`: Validate only CouchDB certificates
- `-v, --verbose`: Enable verbose output (reserved for future use)

## Validation Checks

For each service, the script performs the following validations:

### 1. HTTPS Certificate Validation
- Tests HTTPS connectivity to the service
- Retrieves certificate information via OpenSSL
- Verifies certificate issuer (checks for Let's Encrypt)
- Checks certificate expiration date
- Validates domain presence in Subject Alternative Names (SAN)

### 2. Kubernetes Secret Validation
- Verifies the existence of TLS secrets in the obsidian namespace
- Decodes and analyzes certificates stored in secrets
- Checks certificate expiration dates
- Compares secret certificates with live certificates

### 3. cert-manager Resource Validation
- Checks Certificate resource status
- Verifies cert-manager integration
- Reports on certificate readiness

## Exit Codes

- `0`: All validations passed successfully
- `1`: One or more validations failed

## Output Interpretation

The script uses color-coded output:
- **🔵 [INFO]**: Informational messages
- **🟢 [SUCCESS]**: Successful validations
- **🟡 [WARNING]**: Non-critical issues that should be monitored
- **🔴 [ERROR]**: Critical issues that require attention

### Common Warning Messages

- **"Certificate is not issued by Let's Encrypt"**: The certificate is valid but not from Let's Encrypt (may be expected in some environments)
- **"Certificate expires in X days"**: Certificate is valid but approaching expiration (warning when < 30 days)

### Common Error Messages

- **"Failed to connect to https://domain"**: Network connectivity issues or service not running
- **"Certificate secret not found"**: Kubernetes secret missing or incorrectly named
- **"Certificate has expired"**: Certificate is past its expiration date

## Troubleshooting

If validations fail, check the following:

1. **cert-manager Installation**: Ensure cert-manager is properly installed and running
2. **ClusterIssuer Configuration**: Verify ClusterIssuer resources are available and ready
3. **DNS Resolution**: Confirm domains resolve to the correct IP addresses
4. **Ingress Controller**: Check Traefik ingress controller logs for issues
5. **cert-manager Logs**: Review cert-manager logs for certificate request issues

### Useful Commands

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check ClusterIssuer status
kubectl get clusterissuer

# Check Certificate resources
kubectl get certificates -n obsidian

# View cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check ingress resources
kubectl get ingress -n obsidian
```

## Integration with CI/CD

The script can be integrated into CI/CD pipelines for automated certificate monitoring:

```bash
# Example CI/CD usage
if ./validate-ssl-certificates.sh; then
    echo "Certificate validation passed"
else
    echo "Certificate validation failed"
    exit 1
fi
```

## Monitoring and Alerting

Consider setting up automated monitoring that runs this script periodically and alerts on failures. The script's exit codes and structured output make it suitable for integration with monitoring systems.