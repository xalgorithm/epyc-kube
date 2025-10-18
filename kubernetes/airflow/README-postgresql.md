# PostgreSQL High Availability Setup for Airflow

This directory contains the complete PostgreSQL high availability setup for Apache Airflow, implementing primary-standby streaming replication with automated backups and comprehensive monitoring.

## Architecture Overview

The PostgreSQL HA setup consists of:

- **Primary Database**: Main PostgreSQL instance handling read/write operations
- **Standby Database**: Read-only replica with streaming replication
- **Automated Backups**: Daily backups with retention policies
- **Health Monitoring**: Continuous health checks and replication monitoring
- **Failover Capability**: Manual and automated failover procedures

## Components

### Core Components

| Component | File | Description |
|-----------|------|-------------|
| Namespace | `postgresql-namespace.yaml` | Kubernetes namespace for Airflow |
| Primary DB | `postgresql-primary.yaml` | Primary PostgreSQL StatefulSet and Service |
| Standby DB | `postgresql-standby.yaml` | Standby PostgreSQL StatefulSet and Service |
| Configuration | `postgresql-configmap.yaml` | PostgreSQL configuration and scripts |
| Secrets | `postgresql-secret.yaml` | Database credentials and passwords |
| Storage | `postgresql-storage.yaml` | Persistent volumes and storage classes |

### Backup System

| Component | File | Description |
|-----------|------|-------------|
| Backup Jobs | `postgresql-backup.yaml` | CronJob for automated backups |
| Backup Scripts | Included in ConfigMap | Backup, restore, and cleanup scripts |
| Backup Storage | PVC in backup.yaml | Persistent storage for backup files |

### Monitoring System

| Component | File | Description |
|-----------|------|-------------|
| Health Checks | `postgresql-monitoring.yaml` | Health check CronJob and scripts |
| Monitoring Scripts | Included in ConfigMap | Connection, failover, and replication tests |

### Deployment and Testing

| Component | File | Description |
|-----------|------|-------------|
| Deployment | `deploy-postgresql.sh` | Automated deployment script |
| Testing | `test-postgresql-ha.sh` | Comprehensive test suite |
| Documentation | `README-postgresql.md` | This documentation file |

## Quick Start

### 1. Deploy PostgreSQL HA

```bash
# Navigate to the airflow directory
cd kubernetes/airflow

# Run the deployment script
./deploy-postgresql.sh
```

### 2. Verify Deployment

```bash
# Check pod status
kubectl get pods -n airflow

# Run comprehensive tests
./test-postgresql-ha.sh
```

### 3. Connect to Database

```bash
# Connect to primary database
kubectl exec -it -n airflow postgresql-primary-0 -- psql -U airflow -d airflow

# Connect to standby database (read-only)
kubectl exec -it -n airflow postgresql-standby-0 -- psql -U airflow -d airflow
```

## Configuration

### Database Settings

The PostgreSQL configuration is optimized for high availability:

- **Replication**: Streaming replication with 3 max WAL senders
- **Backup**: WAL archiving enabled for point-in-time recovery
- **Performance**: Tuned for moderate workloads (adjustable)
- **Security**: MD5 authentication with dedicated replication user

### Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| Primary | 1000m | 2000m | 2Gi | 4Gi | 100Gi |
| Standby | 500m | 1000m | 1Gi | 2Gi | 100Gi |
| Backup Job | 100m | 500m | 256Mi | 512Mi | 50Gi |

### Security Configuration

- **Non-root execution**: All containers run as user 999
- **Encrypted passwords**: All passwords stored in Kubernetes secrets
- **Network isolation**: Services only accessible within cluster
- **Replication security**: Dedicated replication user with minimal privileges

## Operations

### Backup Management

#### Manual Backup

```bash
# Create manual backup
kubectl create job --from=cronjob/postgresql-backup manual-backup -n airflow

# Check backup status
kubectl get jobs -n airflow

# View backup logs
kubectl logs job/manual-backup -n airflow
```

#### Restore from Backup

```bash
# List available backups
kubectl exec -n airflow postgresql-primary-0 -- ls -la /var/lib/postgresql/backups/

# Restore from specific backup
kubectl exec -n airflow postgresql-primary-0 -- /scripts/restore.sh postgresql_backup_20240101_020000.sql.gz
```

### Health Monitoring

#### Manual Health Check

```bash
# Run health check
kubectl create job --from=cronjob/postgresql-health-check manual-health -n airflow

# View health check results
kubectl logs job/manual-health -n airflow
```

#### Connection Testing

```bash
# Test primary connection
kubectl exec -n airflow postgresql-primary-0 -- /scripts/connection-test.sh postgresql-primary

# Test standby connection
kubectl exec -n airflow postgresql-primary-0 -- /scripts/connection-test.sh postgresql-standby
```

#### Replication Status

```bash
# Check replication status
kubectl exec -n airflow postgresql-primary-0 -- /scripts/replication-status.sh

# View replication from primary
kubectl exec -n airflow postgresql-primary-0 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Failover Procedures

#### Manual Failover

```bash
# 1. Scale down primary (simulates failure)
kubectl scale statefulset postgresql-primary --replicas=0 -n airflow

# 2. Promote standby to primary
kubectl exec -n airflow postgresql-standby-0 -- touch /tmp/promote_trigger

# 3. Wait for promotion to complete
kubectl exec -n airflow postgresql-standby-0 -- psql -U postgres -c "SELECT pg_is_in_recovery();"

# 4. Update application connection strings to point to standby
```

#### Failover Testing

```bash
# Run comprehensive failover test (destructive)
kubectl exec -n airflow postgresql-primary-0 -- /scripts/failover-test.sh
```

### Scaling and Maintenance

#### Scaling Resources

```bash
# Update resource limits
kubectl patch statefulset postgresql-primary -n airflow -p '{"spec":{"template":{"spec":{"containers":[{"name":"postgresql","resources":{"limits":{"cpu":"4000m","memory":"8Gi"}}}]}}}}'

# Restart pods to apply changes
kubectl rollout restart statefulset/postgresql-primary -n airflow
```

#### Maintenance Mode

```bash
# Put standby in maintenance (stop replication)
kubectl exec -n airflow postgresql-standby-0 -- pg_ctl stop -D /var/lib/postgresql/data/pgdata

# Resume replication
kubectl exec -n airflow postgresql-standby-0 -- pg_ctl start -D /var/lib/postgresql/data/pgdata
```

## Troubleshooting

### Common Issues

#### Replication Not Working

```bash
# Check primary replication slots
kubectl exec -n airflow postgresql-primary-0 -- psql -U postgres -c "SELECT * FROM pg_replication_slots;"

# Check standby recovery status
kubectl exec -n airflow postgresql-standby-0 -- psql -U postgres -c "SELECT pg_is_in_recovery();"

# View standby logs
kubectl logs -n airflow postgresql-standby-0
```

#### High Replication Lag

```bash
# Check replication lag
kubectl exec -n airflow postgresql-standby-0 -- psql -U postgres -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));"

# Check network connectivity
kubectl exec -n airflow postgresql-standby-0 -- ping postgresql-primary
```

#### Backup Failures

```bash
# Check backup job logs
kubectl logs -n airflow $(kubectl get pods -n airflow -l job-name=postgresql-backup -o jsonpath='{.items[0].metadata.name}')

# Check backup storage
kubectl exec -n airflow postgresql-primary-0 -- df -h /var/lib/postgresql/backups
```

#### Pod Startup Issues

```bash
# Check pod events
kubectl describe pod postgresql-primary-0 -n airflow

# Check persistent volume status
kubectl get pv,pvc -n airflow

# Check resource constraints
kubectl top pods -n airflow
```

### Log Analysis

```bash
# View PostgreSQL logs
kubectl logs -n airflow postgresql-primary-0 -f

# View initialization logs
kubectl logs -n airflow postgresql-primary-0 --previous

# Export logs for analysis
kubectl logs -n airflow postgresql-primary-0 > postgresql-primary.log
```

## Security Considerations

### Password Management

1. **Change default passwords** in `postgresql-secret.yaml`
2. **Use strong passwords** for all database users
3. **Rotate passwords regularly** using Kubernetes secret updates
4. **Consider using Vault** for advanced secret management

### Network Security

1. **Network policies** restrict inter-pod communication
2. **TLS encryption** for client connections (configure separately)
3. **Firewall rules** at infrastructure level
4. **VPN access** for administrative operations

### Access Control

1. **RBAC policies** limit Kubernetes access
2. **Database roles** with minimal required privileges
3. **Audit logging** for all database operations
4. **Regular security updates** for PostgreSQL images

## Performance Tuning

### Database Configuration

Key parameters in `postgresql.conf`:

```ini
# Memory settings
shared_buffers = 256MB          # 25% of available memory
effective_cache_size = 1GB      # 75% of available memory
work_mem = 4MB                  # Per-operation memory

# Checkpoint settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB

# Connection settings
max_connections = 200
```

### Storage Optimization

1. **Use SSD storage** for better I/O performance
2. **Separate WAL and data** on different volumes
3. **Monitor disk usage** and plan capacity
4. **Regular VACUUM** and ANALYZE operations

### Monitoring Metrics

Key metrics to monitor:

- **Replication lag**: Should be < 1 second
- **Connection count**: Should be < 80% of max_connections
- **Disk usage**: Should be < 85% full
- **CPU usage**: Should be < 80% average
- **Memory usage**: Should have adequate cache hit ratio

## Integration with Airflow

### Connection Configuration

For Airflow configuration, use these connection parameters:

```yaml
# Primary connection (read/write)
AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql://airflow:password@postgresql-primary.airflow.svc.cluster.local:5432/airflow

# Standby connection (read-only, for reporting)
AIRFLOW__CORE__SQL_ALCHEMY_CONN_READ: postgresql://airflow:password@postgresql-standby.airflow.svc.cluster.local:5432/airflow
```

### High Availability Setup

1. **Connection pooling**: Configure pgbouncer for connection management
2. **Failover detection**: Implement health checks in Airflow
3. **Read replicas**: Use standby for read-only operations
4. **Backup integration**: Coordinate with Airflow backup procedures

## Maintenance Schedule

### Daily Tasks (Automated)

- Database backups at 2 AM UTC
- Health checks every 5 minutes
- Log rotation and cleanup
- Replication status monitoring

### Weekly Tasks (Manual)

- Review backup integrity
- Check replication lag trends
- Update security patches
- Performance metrics review

### Monthly Tasks (Manual)

- Failover testing
- Backup restore testing
- Capacity planning review
- Security audit

## Support and Troubleshooting

### Getting Help

1. **Check logs** first using kubectl logs
2. **Run diagnostics** using provided test scripts
3. **Review metrics** in monitoring dashboards
4. **Consult documentation** for common issues

### Emergency Procedures

1. **Database corruption**: Restore from backup
2. **Replication failure**: Rebuild standby from primary
3. **Storage full**: Emergency cleanup and expansion
4. **Performance issues**: Identify and kill long-running queries

For additional support, refer to the PostgreSQL official documentation and Kubernetes troubleshooting guides.