# Redis Storage Class Fix

## Issue Description

When running `deploy-redis.sh`, the deployment failed with storage class conflicts:

```
PersistentVolumeClaim "redis-data-redis-0" is invalid: spec: Forbidden: spec is immutable after creation except resources.requests and volumeAttributesClassName for bound claims
StorageClassName: &"local-path" -> &"nfs-client"
```

## Root Causes

1. **Storage Class Immutability**: Existing Redis PVCs were created with `local-path` storage class, but the deployment script detected and tried to use `nfs-client`
2. **Security Context Issues**: The Redis StatefulSet had security context violations that prevented pod creation under restricted pod security policies
3. **Sentinel Configuration Issues**: The Redis Sentinel configuration had DNS resolution problems and invalid configuration directives

## Issues Fixed

### 1. Storage Class Conflict
- **Problem**: PVCs existed with `local-path` but script tried to apply `nfs-client`
- **Solution**: Added PVC conflict detection and automatic resolution scripts

### 2. Security Context Violations
- **Problem**: Init container ran as root (`runAsUser: 0`) violating pod security policies
- **Solution**: Updated all containers to run as non-root user (999) with proper security contexts

### 3. Sentinel DNS Resolution
- **Problem**: Sentinel tried to connect to `redis-0.redis-headless.airflow.svc.cluster.local` before DNS was ready
- **Solution**: Changed sentinel to monitor `127.0.0.1` (localhost) since both containers are in the same pod

### 4. Invalid Sentinel Configuration
- **Problem**: `sentinel auth-user` directive was invalid in Redis 7.2
- **Solution**: Removed invalid directive, kept only `requirepass` for authentication

## Files Created/Updated

### Fix Scripts
- `fix-redis-storage-class.sh` - Interactive fix with user confirmation
- `fix-redis-storage-auto.sh` - Automated fix without user interaction

### Updated Configurations
- `redis-statefulset.yaml` - Fixed security contexts and made storage class dynamic
- `redis-configmap.yaml` - Fixed sentinel configuration
- `deploy-redis.sh` - Added PVC conflict detection and dynamic storage class handling

## Solution Implementation

### 1. Storage Class Detection and Conflict Resolution

The deployment script now:
- Detects available storage classes automatically
- Checks for existing PVCs with different storage classes
- Provides clear error messages and fix instructions
- Uses dynamic storage class replacement in StatefulSet

### 2. Security Context Hardening

All containers now have proper security contexts:
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsUser: 999
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

### 3. Simplified Sentinel Configuration

```yaml
# Before (problematic)
sentinel monitor mymaster redis-0.redis-headless.airflow.svc.cluster.local 6379 2
sentinel auth-user default ${REDIS_PASSWORD}

# After (working)
sentinel monitor mymaster 127.0.0.1 6379 2
requirepass ${REDIS_PASSWORD}
```

## Usage

### Automatic Fix (Recommended)
```bash
./fix-redis-storage-auto.sh
./deploy-redis.sh
```

### Interactive Fix
```bash
./fix-redis-storage-class.sh
./deploy-redis.sh
```

### Manual Fix
```bash
# Scale down StatefulSet
kubectl scale statefulset redis -n airflow --replicas=0

# Delete conflicting PVCs
kubectl delete pvc -l app.kubernetes.io/name=redis -n airflow

# Deploy with correct storage class
./deploy-redis.sh
```

## Verification

After successful deployment:

```bash
# Check pod status
kubectl get pods -n airflow -l app.kubernetes.io/name=redis

# Test Redis connectivity
kubectl exec -n airflow redis-0 -c redis -- redis-cli -a airflow-redis-2024 ping

# Test Sentinel connectivity
kubectl exec -n airflow redis-0 -c sentinel -- redis-cli -p 26379 -a airflow-redis-2024 ping

# Check Sentinel status
kubectl exec -n airflow redis-0 -c sentinel -- redis-cli -p 26379 -a airflow-redis-2024 sentinel masters

# Check storage
kubectl get pvc -n airflow -l app.kubernetes.io/name=redis
```

## Prevention

To prevent similar issues in the future:

1. **Always check for existing PVCs** before deploying with different storage classes
2. **Use dynamic storage class detection** instead of hardcoded values
3. **Test security contexts** against pod security policies
4. **Validate configuration files** before deployment
5. **Use localhost for co-located containers** instead of DNS names when possible

## Related Files

- `redis-statefulset.yaml` - Updated StatefulSet with security fixes
- `redis-configmap.yaml` - Fixed Redis and Sentinel configuration
- `deploy-redis.sh` - Enhanced deployment script with conflict detection
- `fix-redis-storage-class.sh` - Interactive storage fix script
- `fix-redis-storage-auto.sh` - Automated storage fix script