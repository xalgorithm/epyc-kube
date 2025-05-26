# Grafana Security Guide

This document explains the secure management of Grafana credentials using HashiCorp Vault.

## Overview

All Grafana credentials have been moved from scripts, configuration files, and Kubernetes secrets to HashiCorp Vault. This provides:

1. Centralized secrets management
2. Audit trail for secret access
3. Dynamic secret rotation
4. Integration with Kubernetes

## Setup Instructions

### 1. Store Credentials in Vault

Run the `store-credentials-in-vault.sh` script to store Grafana credentials in Vault:

```bash
# Set your Vault environment variables
export VAULT_ADDR=https://vault.example.com:8200
export VAULT_TOKEN=your-vault-token

# Run the script
./store-credentials-in-vault.sh
```

### 2. Update Grafana Secret for Vault Integration

Run the `update-grafana-secret-for-vault.sh` script to update the Kubernetes secret:

```bash
./update-grafana-secret-for-vault.sh
```

### 3. Update Grafana Deployment

Run the `update-grafana-deployment-for-vault.sh` script to update the Grafana deployment:

```bash
./update-grafana-deployment-for-vault.sh
```

### 4. Remove Credentials from Files

Run the `remove-credentials-from-files.sh` script to back up and remove credentials from files:

```bash
./remove-credentials-from-files.sh
```

## Using Credentials Securely

All scripts have been updated to retrieve credentials from Vault rather than using hardcoded values. Example:

```bash
# Get credentials from Vault
ADMIN_USER=$(vault kv get -field=username secret/grafana/admin)
ADMIN_PASSWORD=$(vault kv get -field=password secret/grafana/admin)

# Use the credentials
curl -u "$ADMIN_USER:$ADMIN_PASSWORD" https://grafana.example.com/api/...
```

## Accessing the Web UI

To log in to Grafana, retrieve the credentials from Vault:

```bash
vault kv get secret/grafana/admin
# or
vault kv get -field=username secret/grafana/admin
vault kv get -field=password secret/grafana/admin
```

## Vault Structure

Grafana credentials are stored in Vault with the following structure:

- `secret/grafana/admin` - Admin credentials
  - `username` - Admin username
  - `password` - Admin password
- `secret/grafana/xalg` - User credentials
  - `username` - User username
  - `password` - User password

## Best Practices

1. Never hardcode credentials in scripts or configuration files
2. Use environment variables for temporary credential storage
3. Limit Vault token permissions using policies
4. Rotate Vault tokens regularly
5. Audit Vault access logs
6. Use the Vault Agent sidecar for Kubernetes integration

## Troubleshooting

If you encounter issues with Vault integration:

1. Check Vault server status
2. Verify Vault token permissions
3. Check Kubernetes service account and role bindings
4. Review Vault agent logs in the Grafana pod
5. Ensure Vault's Kubernetes auth method is properly configured

For more information, refer to the [Vault documentation](https://www.vaultproject.io/docs). 