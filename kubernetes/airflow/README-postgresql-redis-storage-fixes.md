# PostgreSQL and Redis Storage Class Fixes

This document summarizes the fixes applied to the PostgreSQL and Redis deployment scripts to work with the NFS storage class and provide better storage class detection.

## Overview

Both `deploy-postgresql.sh` and `deploy-redis.sh` have been updated to:
1. **Automatically detect** available storage classes
2. **Dynamically generate** storage configurations
3. **Prioritize NFS storage** for production workloads
4. **Provide better error handling** and logging
5. **Wait for PVC binding** before proceeding with deployments

## Key Changes

### 1. Storage Class Detection

Both scripts now include intelligent storage class detection:

```bash
# Priority order:
1. nfs-client (recommended for production)
2. local-path (acceptable for development)
3. Any NFS-based storage class
4. Default storage class (fallback)
```

### 2. Dynamic Storage Configuration

Instead of using static YAML files with hardcoded storage classes, the scripts now:
- Generate storage configurations at runtime
- Use the detected storage class
- Create temporary configuration files
- Clean up generated files during cleanup

### 3. Enhanced Error Handling

Improved error handling includes:
- PVC binding validation
- Storage class availability checks
- Timeout handling for storage operations
- Detailed error messages with troubleshooting guidance

### 4. Better Logging and Status

Enhanced logging provides:
- Color-coded output for better visibility
- Progress indicators for long-running operations
- Storage configuration summaries
- Troubleshooting commands

## PostgreSQL Script Changes

### Modified Functions

1. **`detect_storage_class()`** - New function to detect available storage classes
2. **`create_storage_config()`** - Generates dynamic storage configuration
3. **`wait_for_pvcs()`** - Waits for PVCs to be bound before proceeding
4. **Enhanced logging** - All steps now use structured logging

### Generated Files

The script creates `postgresql-storage-dynamic.yaml` with:
- Detected storage class
- Consistent PVC naming
- Proper labels and annotations
- 100Gi storage per instance

### Example Generated Configuration

```yaml
# PostgreSQL Storage Configuration - Auto-generated
# Uses detected storage class: nfs-client

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-primary-pvc
  namespace: airflow
  labels:
    app: postgresql
    component: primary
    storage-class: nfs-client
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-client
  resources:
    requests:
      storage: 100Gi
```

## Redis Script Changes

### Modified Functions

1. **`detect_storage_class()`** - Same detection logic as PostgreSQL
2. **`create_redis_storage_config()`** - Generates Redis-specific storage config
3. **`wait_for_redis_pvcs()`** - Waits for all 3 Redis PVCs to be bound
4. **Enhanced deployment flow** - Storage validation before StatefulSet deployment

### Generated Files

The script creates `redis-storage-dynamic.yaml` with:
- 3 PVCs for Redis instances (redis-0, redis-1, redis-2)
- 10Gi storage per instance
- Detected storage class
- Proper labels for Redis components

### Example Generated Configuration

```yaml
# Redis Storage Configuration - Auto-generated
# Uses detected storage class: nfs-client

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data-redis-0
  namespace: airflow
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: storage
    storage-class: nfs-client
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: nfs-client
```

## Storage Class Compatibility

### Supported Storage Classes

| Storage Class | Status | Use Case | Notes |
|---------------|--------|----------|-------|
| `nfs-client` | ✅ Recommended | Production | Best performance, ReadWriteMany support |
| `local-path` | ⚠️ Acceptable | Development | Single-node clusters only |
| Custom NFS | ✅ Good | Production | Auto-detected NFS provisioners |
| Default SC | ⚠️ Fallback | Various | Uses cluster default |

### Storage Requirements

**PostgreSQL:**
- Access Mode: ReadWriteOnce
- Size: 100Gi per instance (primary + standby = 200Gi total)
- Recommended: NFS or high-performance block storage

**Redis:**
- Access Mode: ReadWriteOnce
- Size: 10Gi per instance (3 instances = 30Gi total)
- Recommended: Fast storage for caching performance

## Usage Examples

### PostgreSQL Deployment

```bash
# Deploy with automatic storage detection
./deploy-postgresql.sh

# The script will:
# 1. Detect available storage classes
# 2. Generate storage configuration
# 3. Create PVCs and wait for binding
# 4. Deploy PostgreSQL primary and standby
# 5. Verify replication setup
```

### Redis Deployment

```bash
# Deploy Redis Sentinel cluster
./deploy-redis.sh deploy

# Check status
./deploy-redis.sh status

# Test functionality
./deploy-redis.sh test

# Clean up
./deploy-redis.sh cleanup
```

## Troubleshooting

### Common Issues and Solutions

#### Issue: Storage Class Not Found

**Symptoms:**
```
✗ No suitable storage class found
Please install a storage provisioner (NFS recommended)
```

**Solution:**
```bash
# Check available storage classes
kubectl get storageclass

# Install NFS provisioner if needed
# Or use existing storage class
```

#### Issue: PVCs Stuck in Pending

**Symptoms:**
```
Timeout waiting for postgresql-primary-pvc to bind
Check storage class and provisioner: nfs-client
```

**Solution:**
```bash
# Check storage class details
kubectl describe storageclass nfs-client

# Check PVC events
kubectl describe pvc postgresql-primary-pvc -n airflow

# Verify provisioner is running
kubectl get pods -n kube-system | grep nfs
```

#### Issue: Storage Class Mismatch

**Symptoms:**
- Different components using different storage classes
- Inconsistent performance

**Solution:**
```bash
# Check current storage configuration
./check-airflow-storage.sh consistency

# Redeploy with consistent storage class
./deploy-postgresql.sh
./deploy-redis.sh deploy
```

### Diagnostic Commands

```bash
# Check overall storage status
./check-airflow-storage.sh

# Check PostgreSQL storage specifically
./check-airflow-storage.sh postgresql

# Check available storage classes
./check-airflow-storage.sh storage-classes

# Check PVC status
kubectl get pvc -n airflow

# Check storage class details
kubectl describe storageclass nfs-client
```

## Integration with Other Components

### Airflow Deployment

The main Airflow deployment script (`deploy-airflow.sh`) has been updated to:
- Validate PostgreSQL and Redis storage before deployment
- Use the same storage class detection logic
- Provide comprehensive storage status information

### Storage Monitoring

Storage monitoring works with the new configuration:
- Prometheus metrics for all PVCs
- Grafana dashboards show storage usage
- Alerts for storage capacity and performance

### Backup and Recovery

Backup procedures work with any storage class:
- PostgreSQL backups use the same storage class
- Redis persistence uses the configured storage
- Backup retention policies apply consistently

## File Changes Summary

### Modified Files

1. **`deploy-postgresql.sh`**
   - Added storage class detection
   - Dynamic storage configuration generation
   - Enhanced error handling and logging
   - PVC binding validation

2. **`deploy-redis.sh`**
   - Added storage class detection
   - Dynamic Redis storage configuration
   - Improved deployment flow
   - Enhanced status reporting

### Generated Files (Temporary)

1. **`postgresql-storage-dynamic.yaml`** - Generated PostgreSQL storage config
2. **`redis-storage-dynamic.yaml`** - Generated Redis storage config

These files are created during deployment and cleaned up during cleanup operations.

### Existing Files (Still Used)

1. **`postgresql-storage.yaml`** - Original static configuration (fallback)
2. **`redis-storage.yaml`** - Original static configuration (fallback)
3. **`postgresql-storage-simple.yaml`** - Simplified configuration for fixes

## Best Practices

### 1. Storage Class Selection

**Production Environments:**
- Use NFS-based storage classes for shared access
- Ensure high availability and performance
- Plan for backup and disaster recovery

**Development Environments:**
- Local-path storage is acceptable
- Consider resource constraints
- Use smaller storage sizes

### 2. Monitoring and Maintenance

- Monitor PVC usage regularly
- Set up alerts for storage capacity
- Plan for storage growth
- Test backup and restore procedures

### 3. Troubleshooting Workflow

1. **Check storage status**: `./check-airflow-storage.sh`
2. **Verify storage classes**: `kubectl get storageclass`
3. **Check PVC events**: `kubectl describe pvc <pvc-name> -n airflow`
4. **Review provisioner logs**: Check storage provisioner pods
5. **Apply fixes**: Use appropriate fix scripts

## Future Improvements

### Planned Enhancements

1. **Storage migration tools** - Migrate between storage classes
2. **Automatic storage sizing** - Based on workload requirements
3. **Multi-zone storage** - For high availability deployments
4. **Storage performance tuning** - Optimize for specific workloads

### Considerations

1. **Cost optimization** - Storage tier management
2. **Performance monitoring** - Storage I/O metrics
3. **Compliance requirements** - Data residency and encryption
4. **Disaster recovery** - Cross-region backup strategies

## Conclusion

These improvements make PostgreSQL and Redis deployments more robust and adaptable:

- **Automatic storage detection** eliminates manual configuration
- **Dynamic configuration generation** adapts to different environments
- **Enhanced error handling** provides better troubleshooting
- **Consistent storage usage** across all components

The changes ensure that both PostgreSQL and Redis work seamlessly with the NFS storage class while maintaining compatibility with other storage provisioners.