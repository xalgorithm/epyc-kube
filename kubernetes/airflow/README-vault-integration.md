# Airflow Vault Integration

This document describes the HashiCorp Vault integration for Apache Airflow secrets management, implementing secure credential storage and automated secret rotation.

## Overview

The Vault integration provides:
- Centralized secret management for all Airflow credentials
- Automated secret synchronization to Kubernetes
- Secret rotation policies with automated updates
- Secure storage of database, Redis, and application secrets

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   HashiCorp     │    │ Vault Secrets   │    │   Kubernetes    │
│     Vault       │◄───│   Operator      │◄───│    Secrets      │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │ stores                │ syncs                 │ consumes
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Airflow Secrets │    │ Secret Templates│    │ Airflow Pods    │
│ - Database      │    │ - Annotations   │    │ - Webserver     │
│ - Redis         │    │ - Templates     │    │ - Scheduler     │
│ - Webserver     │    │ - Policies      │    │ - Workers       │
│ - Connections   │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Secret Paths in Vault

The following secret paths are created in Vault:

### `secret/airflow/database`
Database connection credentials:
- `username`: PostgreSQL username
- `password`: PostgreSQL password  
- `database`: Database name
- `host`: Database host
- `port`: Database port
- `connection_string`: Full connection string

### `secret/airflow/redis`
Redis authentication credentials:
- `password`: Redis password
- `host`: Redis host
- `port`: Redis port
- `database`: Redis database number
- `connection_string`: Full connection string

### `secret/airflow/webserver`
Airflow application secrets:
- `fernet_key`: Airflow Fernet encryption key
- `webserver_secret_key`: Flask secret key
- `admin_username`: Default admin username
- `admin_password`: Default admin password
- `admin_email`: Admin email address

### `secret/airflow/connections`
External service connections:
- `smtp_host`: SMTP server host
- `smtp_port`: SMTP server port
- `smtp_username`: SMTP username
- `smtp_password`: SMTP password
- `slack_webhook`: Slack webhook URL
- `aws_access_key_id`: AWS access key
- `aws_secret_access_key`: AWS secret key

## Kubernetes Secrets

The Vault Secrets Operator creates the following Kubernetes secrets:

- `airflow-database-secret`: Database credentials
- `airflow-redis-secret`: Redis credentials
- `airflow-webserver-secret`: Application secrets
- `airflow-connections-secret`: External connections

## Deployment

### Prerequisites

1. HashiCorp Vault must be deployed and initialized
2. Vault Secrets Operator must be running
3. Airflow namespace must exist

### Step 1: Set up Vault Secrets

```bash
# Set up Airflow secrets in Vault
./setup-airflow-vault-secrets.sh
```

### Step 2: Deploy Vault Integration

```bash
# Deploy Vault secret templates and policies
./deploy-airflow-vault-integration.sh
```

### Step 3: Deploy Secret Rotation

```bash
# Deploy secret rotation policies
kubectl apply -f airflow-secret-rotation-policy.yaml
```

### Step 4: Test Integration

```bash
# Test the Vault integration
./test-airflow-vault-integration.sh
```

## Secret Rotation

### Automatic Rotation

Secrets are automatically rotated based on the following schedule:

- **Database secrets**: Every 90 days
- **Redis secrets**: Every 60 days  
- **Webserver secrets**: Every 30 days
- **Connection secrets**: Every 180 days (manual approval required)

### Rotation Process

1. **Check**: CronJob runs daily at 2 AM to check rotation needs
2. **Generate**: New secure passwords/keys are generated
3. **Update**: Vault secrets are updated with new values
4. **Sync**: Vault Secrets Operator syncs to Kubernetes
5. **Notify**: Notifications sent via ntfy and email
6. **Restart**: Dependent services are restarted to use new secrets

### Manual Rotation

To manually rotate a secret:

```bash
# Rotate database password
kubectl create job --from=cronjob/airflow-secret-rotation manual-rotation-$(date +%s) -n airflow

# Or rotate specific secret via Vault CLI
vault kv put secret/airflow/database \
  username=airflow \
  password="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-25)" \
  database=airflow \
  host=postgresql-primary \
  port=5432
```

## Security Features

### Encryption
- All secrets encrypted at rest in Vault
- TLS encryption for Vault communication
- Kubernetes secrets encrypted with etcd encryption

### Access Control
- Vault policies restrict access to Airflow secrets
- Kubernetes RBAC controls secret access
- Service accounts with minimal permissions

### Audit Logging
- Vault audit logs all secret access
- Kubernetes audit logs secret operations
- Rotation events logged and monitored

### Backup and Recovery
- Vault data backed up with cluster backups
- Secret recovery procedures documented
- Emergency access procedures defined

## Monitoring and Alerting

### Metrics
- Secret rotation success/failure rates
- Secret age and expiration tracking
- Vault Secrets Operator sync status

### Alerts
- Secret rotation failures
- Vault connectivity issues
- Secret sync failures
- Approaching expiration dates

### Notifications
- ntfy notifications for rotation events
- Email alerts for critical failures
- Slack integration for team notifications

## Troubleshooting

### Common Issues

#### Secrets Not Syncing
```bash
# Check Vault Secrets Operator logs
kubectl logs -n vault-secrets -l app=vault-secrets-operator

# Verify Vault connectivity
kubectl exec -n vault-secrets deployment/vault-secrets-operator -- \
  wget -qO- http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

#### Rotation Failures
```bash
# Check rotation job logs
kubectl logs -n airflow job/airflow-secret-rotation-<timestamp>

# Verify Vault token permissions
vault token lookup
```

#### Authentication Errors
```bash
# Check Vault credentials
kubectl get secret vault-credentials -n airflow -o yaml

# Test Vault authentication
vault auth -method=approle role_id=$VAULT_ROLE_ID secret_id=$VAULT_SECRET_ID
```

### Recovery Procedures

#### Vault Unavailable
1. Check Vault pod status and logs
2. Verify persistent volume availability
3. Unseal Vault if necessary
4. Restart Vault Secrets Operator

#### Secret Corruption
1. Restore from Vault backup
2. Regenerate corrupted secrets
3. Force sync with Vault Secrets Operator
4. Restart affected Airflow components

#### Emergency Access
1. Use Vault root token for emergency access
2. Manually create Kubernetes secrets if needed
3. Update Airflow configuration temporarily
4. Restore normal operation after resolution

## Files

- `setup-airflow-vault-secrets.sh`: Sets up secrets in Vault
- `deploy-airflow-vault-integration.sh`: Deploys Vault integration
- `airflow-vault-secrets.yaml`: Kubernetes secret templates
- `airflow-secret-rotation-policy.yaml`: Rotation policies and CronJob
- `test-airflow-vault-integration.sh`: Integration tests
- `airflow-values.yaml`: Updated Helm values for Vault integration

## Security Considerations

1. **Root Token**: Secure the Vault root token and rotate regularly
2. **AppRole Credentials**: Protect role_id and secret_id values
3. **Network Security**: Use network policies to restrict Vault access
4. **Backup Security**: Encrypt Vault backups and store securely
5. **Audit Compliance**: Enable comprehensive audit logging
6. **Access Reviews**: Regularly review and update access policies