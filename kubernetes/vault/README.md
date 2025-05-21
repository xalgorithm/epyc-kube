# Secure Credential Management with HashiCorp Vault

This directory contains configuration files and scripts to deploy HashiCorp Vault for secure credential management in the Kubernetes cluster.

## Architecture

```
┌───────────────┐                ┌───────────────┐
│ Vault Server  │◀───────────────│ Vault UI      │
│ (StatefulSet) │                │ (Ingress)     │
└───────┬───────┘                └───────────────┘
        │
        │ stores
        ▼
┌───────────────┐                ┌───────────────┐
│ Persistent    │                │ Vault Secrets │
│ Volume        │                │ Operator      │
└───────────────┘                └───────┬───────┘
                                         │
                                         │ syncs
                                         ▼
┌────────────────────────────────────────────────┐
│                                                │
│             Kubernetes Secrets                 │
│                                                │
└────────────────────────────────────────────────┘
       │                 │                 │
       ▼                 ▼                 ▼
┌──────────┐      ┌──────────┐      ┌──────────┐
│ n8n      │      │ CouchDB  │      │ Alert    │
│ Secret   │      │ Secret   │      │ Manager  │
└──────────┘      └──────────┘      └──────────┘
```

## Components

- **Vault Server**: Core component that stores and manages secrets
- **Vault UI**: Web interface for managing secrets
- **Vault Secrets Operator**: Syncs secrets from Vault to Kubernetes
- **Persistent Volume**: Ensures data durability

## Initial Setup

To deploy Vault and configure it with initial secrets:

```bash
# Deploy and initialize Vault with secure password
VAULT_PASSWORD="your-secure-password" SMTP_PASSWORD="your-email-app-password" ./deploy-vault.sh

# Deploy the Vault Secrets Operator
./deploy-secrets-operator.sh
```

## Default Credentials

The initial root password for accessing Vault is set to:
```
******** (defined in deploy-vault.sh)
```

**IMPORTANT**: Change this password after initial login!

## Files in this Directory

- `vault-config.yaml` - Vault server deployment configuration
- `vault-ingress.yaml` - Ingress configuration for the Vault UI
- `vault-secret-manager.yaml` - Vault Secrets Operator configuration
- `deploy-vault.sh` - Script to deploy and configure Vault
- `deploy-secrets-operator.sh` - Script to deploy the Secrets Operator

## Security Considerations

1. **Root Token**: The root token should be revoked after setting up auth methods
2. **Unseal Keys**: These are critical for disaster recovery
3. **Backup**: Regular backups of Vault data are essential
4. **Audit Logging**: Enable audit logging for traceability

## Accessing Secrets

### CLI Access

```bash
# Source environment variables
source ~/.vault/credentials

# Set Vault address
export VAULT_ADDR=https://vault.gray-beard.com

# Login with token
vault login -method=token "$VAULT_ROOT_TOKEN"

# List secrets
vault kv list secret

# Read a secret
vault kv get secret/n8n
```

### Web UI Access

The Vault UI is available at: `https://vault.gray-beard.com`

## Available Secret Paths

- `secret/alertmanager` - AlertManager email configuration
- `secret/n8n` - n8n admin credentials
- `secret/couchdb` - CouchDB credentials
- `secret/k3s` - K3s cluster token

## Troubleshooting

- If Vault is sealed, use the unseal key stored in `~/.vault/credentials`
- Check operator logs with: `kubectl logs -n vault-secrets -l app=vault-secrets-operator` 