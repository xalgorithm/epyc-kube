# Redis Sentinel Cluster for Airflow

This directory contains the Redis Sentinel cluster deployment for Apache Airflow message queuing. The deployment provides high availability, automatic failover, and comprehensive monitoring for Airflow's Celery executor.

## Architecture

The Redis deployment consists of:

- **3 Redis instances** in a StatefulSet with persistence
- **3 Sentinel instances** (co-located with Redis) for automatic failover
- **Connection pooling** with automatic failover logic
- **Monitoring** with Prometheus metrics export
- **Health checking** scripts for operational monitoring

## Components

### Core Components

| Component | Description | Replicas |
|-----------|-------------|----------|
| Redis StatefulSet | Redis server instances with persistence | 3 |
| Sentinel | Failover coordination and master discovery | 3 |
| Headless Service | Service discovery for StatefulSet pods | 1 |
| Redis Service | Load-balanced access to Redis | 1 |
| Sentinel Service | Load-balanced access to Sentinel | 1 |

### Storage

| Component | Size | Access Mode | Purpose |
|-----------|------|-------------|---------|
| Redis Data PVC | 10Gi | ReadWriteOnce | Redis data persistence |

### Configuration

| ConfigMap | Purpose |
|-----------|---------|
| redis-config | Redis and Sentinel configuration |
| redis-persistence-config | Detailed persistence settings |
| redis-connection-pool | Python connection pool implementation |
| redis-monitoring-scripts | Health check and monitoring scripts |

## Deployment

### Prerequisites

- Kubernetes cluster with StorageClass `local-path`
- kubectl configured for cluster access
- Namespace `airflow` (created automatically)

### Deploy Redis Cluster

```bash
# Deploy the complete Redis Sentinel cluster
./deploy-redis.sh

# Deploy only monitoring components
./deploy-redis.sh monitoring

# Check deployment status
./deploy-redis.sh status
```

### Test Deployment

```bash
# Run comprehensive HA tests
./test-redis-ha.sh

# Run specific tests
./test-redis-ha.sh connectivity
./test-redis-ha.sh replication
./test-redis-ha.sh failover

# Generate test report
./test-redis-ha.sh report
```

## Configuration

### Redis Configuration

The Redis instances are configured with:

- **Persistence**: Both RDB snapshots and AOF logging
- **Memory Policy**: `allkeys-lru` for automatic eviction
- **Security**: Password authentication required
- **Replication**: Automatic slave synchronization

### Sentinel Configuration

The Sentinel instances provide:

- **Quorum**: 2 out of 3 Sentinels required for failover
- **Monitoring**: Continuous master health checking
- **Failover**: Automatic promotion of slaves to master
- **Discovery**: Service discovery for clients

### Connection Pool Configuration

The connection pool provides:

- **Automatic Failover**: Transparent failover to new master
- **Connection Reuse**: Efficient connection pooling
- **Health Checking**: Continuous connection validation
- **Load Balancing**: Read operations can use slaves

## Usage

### Airflow Integration

For Airflow Celery executor, use this broker URL:

```python
CELERY_BROKER_URL = "sentinel://:password@redis-0.redis-headless.airflow.svc.cluster.local:26379;redis-1.redis-headless.airflow.svc.cluster.local:26379;redis-2.redis-headless.airflow.svc.cluster.local:26379/0?sentinel_service_name=mymaster"
```

### Direct Redis Access

```bash
# Connect to Redis service
redis-cli -h redis.airflow.svc.cluster.local -p 6379 -a <password>

# Connect to specific Redis instance
redis-cli -h redis-0.redis-headless.airflow.svc.cluster.local -p 6379 -a <password>

# Connect to Sentinel
redis-cli -h redis-sentinel.airflow.svc.cluster.local -p 26379 -a <password>
```

### Python Connection Example

```python
from redis_connection_pool import get_redis_pool

# Get connection pool
pool = get_redis_pool()

# Use connection for writes (master)
with pool.get_connection() as conn:
    conn.set('key', 'value')

# Use connection for reads (slave preferred)
with pool.get_connection(read_only=True) as conn:
    value = conn.get('key')

# Check cluster health
health = pool.health_check()
print(health)
```

## Monitoring

### Prometheus Metrics

The deployment includes a Redis exporter that provides metrics:

- **redis_up**: Instance availability
- **redis_connected_clients**: Number of connected clients
- **redis_used_memory_bytes**: Memory usage
- **redis_commands_processed_total**: Command statistics
- **redis_keyspace_hits_total**: Cache hit statistics
- **redis_replication_lag_seconds**: Replication lag

### Health Checks

```bash
# Run health check script
kubectl exec -n airflow redis-0 -c redis -- /scripts/redis-health-check.sh

# Monitor cluster in real-time
kubectl exec -n airflow redis-0 -c redis -- python /scripts/redis-cluster-monitor.py dashboard

# Export status to JSON
kubectl exec -n airflow redis-0 -c redis -- python /scripts/redis-cluster-monitor.py export
```

### Grafana Dashboards

The deployment is compatible with standard Redis Grafana dashboards:

- Redis Overview Dashboard
- Redis Sentinel Dashboard
- Custom Airflow Redis Dashboard

## High Availability

### Automatic Failover

The Sentinel cluster provides automatic failover:

1. **Detection**: Sentinels detect master failure (5 second timeout)
2. **Quorum**: 2 out of 3 Sentinels must agree on failure
3. **Election**: Sentinels elect a new master from available slaves
4. **Promotion**: Selected slave is promoted to master
5. **Notification**: Clients are notified of the new master

### Split-Brain Prevention

- **Quorum Requirement**: Minimum 2 Sentinels required for decisions
- **Master Validation**: Multiple validation checks before failover
- **Client Coordination**: Clients use Sentinel for master discovery

### Data Persistence

- **RDB Snapshots**: Periodic snapshots for point-in-time recovery
- **AOF Logging**: Append-only file for durability
- **Persistent Volumes**: Data survives pod restarts
- **Backup Integration**: Ready for external backup systems

## Troubleshooting

### Common Issues

#### Master Not Found
```bash
# Check Sentinel status
kubectl exec -n airflow redis-0 -c sentinel -- redis-cli -p 26379 -a <password> sentinel masters

# Check master discovery
kubectl exec -n airflow redis-0 -c sentinel -- redis-cli -p 26379 -a <password> sentinel get-master-addr-by-name mymaster
```

#### Replication Lag
```bash
# Check replication status
kubectl exec -n airflow redis-0 -c redis -- redis-cli -a <password> info replication

# Check network connectivity between pods
kubectl exec -n airflow redis-0 -- ping redis-1.redis-headless.airflow.svc.cluster.local
```

#### High Memory Usage
```bash
# Check memory usage
kubectl exec -n airflow redis-0 -c redis -- redis-cli -a <password> info memory

# Check key distribution
kubectl exec -n airflow redis-0 -c redis -- redis-cli -a <password> info keyspace
```

### Log Analysis

```bash
# View Redis logs
kubectl logs -n airflow redis-0 -c redis

# View Sentinel logs
kubectl logs -n airflow redis-0 -c sentinel

# View all logs with timestamps
kubectl logs -n airflow redis-0 -c redis --timestamps=true
kubectl logs -n airflow redis-0 -c sentinel --timestamps=true
```

### Performance Tuning

#### Memory Optimization
- Adjust `maxmemory-policy` based on workload
- Monitor key expiration patterns
- Consider memory-efficient data structures

#### Network Optimization
- Tune `tcp-keepalive` settings
- Adjust connection pool sizes
- Monitor connection patterns

#### Persistence Optimization
- Balance RDB and AOF settings
- Adjust `save` intervals based on data importance
- Monitor disk I/O patterns

## Security

### Authentication
- Password-based authentication enabled
- Separate passwords for Redis and Sentinel
- Kubernetes secrets for credential management

### Network Security
- Internal cluster communication only
- Network policies for traffic restriction
- TLS encryption (can be enabled)

### Access Control
- RBAC for Kubernetes resources
- Service account restrictions
- Pod security contexts

## Backup and Recovery

### Backup Strategy
```bash
# Manual backup
kubectl exec -n airflow redis-0 -c redis -- redis-cli -a <password> bgsave

# Copy RDB file
kubectl cp airflow/redis-0:/data/dump.rdb ./redis-backup-$(date +%Y%m%d).rdb
```

### Recovery Process
```bash
# Stop Redis
kubectl scale statefulset -n airflow redis --replicas=0

# Restore RDB file
kubectl cp ./redis-backup.rdb airflow/redis-0:/data/dump.rdb

# Start Redis
kubectl scale statefulset -n airflow redis --replicas=3
```

## Cleanup

```bash
# Remove Redis deployment
./deploy-redis.sh cleanup

# Manual cleanup
kubectl delete -f redis-statefulset.yaml
kubectl delete -f redis-service.yaml
kubectl delete -f redis-headless-service.yaml
kubectl delete pvc -n airflow -l app.kubernetes.io/name=redis
```

## Files Reference

| File | Purpose |
|------|---------|
| `deploy-redis.sh` | Main deployment script |
| `test-redis-ha.sh` | High availability testing |
| `redis-statefulset.yaml` | Redis StatefulSet definition |
| `redis-service.yaml` | Service definitions |
| `redis-configmap.yaml` | Redis configuration |
| `redis-secret.yaml` | Authentication credentials |
| `redis-storage.yaml` | Persistent volume claims |
| `redis-monitoring.yaml` | Monitoring scripts |
| `redis-servicemonitor.yaml` | Prometheus integration |
| `redis-connection-pool.yaml` | Python connection pool |

## Support

For issues and questions:

1. Check the troubleshooting section
2. Run the health check scripts
3. Review pod logs
4. Test with the HA testing script
5. Consult Redis and Sentinel documentation

## Requirements Satisfied

This implementation satisfies the following requirements:

- **5.1**: Horizontal pod autoscaling for worker nodes (Redis provides the message queue)
- **5.2**: Automatic scaling based on queue length (Redis queue depth monitoring)
- **5.3**: Automatic scale-down when queue length decreases (Redis queue monitoring)

The Redis Sentinel cluster provides the reliable message queuing infrastructure needed for Airflow's Celery executor to implement these scaling behaviors.