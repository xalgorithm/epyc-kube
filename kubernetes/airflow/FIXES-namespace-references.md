# Fixed Namespace Reference Issues

## Summary

Fixed outdated file references in deployment scripts that were pointing to non-existent namespace files.

## Issues Fixed

### 1. PostgreSQL Deployment Script (`deploy-postgresql.sh`)

**Issue**: Script was referencing `postgresql-namespace.yaml` which doesn't exist.

**Fix**: Updated to reference `airflow-namespace-rbac.yaml` which contains the namespace definition.

**Change**:
```bash
# Before
kubectl apply -f postgresql-namespace.yaml

# After  
kubectl apply -f airflow-namespace-rbac.yaml
```

### 2. Redis Deployment Script (`deploy-redis.sh`)

**Issue**: Script was referencing `redis-namespace.yaml` which doesn't exist.

**Fix**: Updated to reference `airflow-namespace-rbac.yaml` which contains the namespace definition.

**Change**:
```bash
# Before
kubectl apply -f "$SCRIPT_DIR/redis-namespace.yaml"

# After
kubectl apply -f "$SCRIPT_DIR/airflow-namespace-rbac.yaml"
```

## Verification

### Files Verified to Exist
All deployment scripts now reference existing files:

- ✅ `airflow-namespace-rbac.yaml` - Contains namespace and RBAC definitions
- ✅ `postgresql-storage.yaml` - PostgreSQL storage configuration
- ✅ `postgresql-secret.yaml` - PostgreSQL secrets
- ✅ `postgresql-configmap.yaml` - PostgreSQL configuration
- ✅ `postgresql-primary.yaml` - Primary PostgreSQL instance
- ✅ `postgresql-standby.yaml` - Standby PostgreSQL instance
- ✅ `postgresql-backup.yaml` - Backup configuration
- ✅ `postgresql-monitoring.yaml` - Monitoring setup
- ✅ All Redis configuration files
- ✅ All Airflow configuration files

### Scripts Validated
- ✅ `deploy-postgresql.sh` - Syntax check passed
- ✅ `deploy-redis.sh` - Syntax check passed
- ✅ All referenced YAML files validated with `kubectl apply --dry-run=client`

## Impact

These fixes ensure that:

1. **PostgreSQL deployment** will work correctly without failing on missing namespace file
2. **Redis deployment** will work correctly without failing on missing namespace file
3. **Namespace creation** is handled consistently across all deployment scripts
4. **RBAC configuration** is applied properly for all components

## Next Steps

The deployment scripts are now ready to use:

```bash
# Deploy PostgreSQL
./deploy-postgresql.sh

# Deploy Redis  
./deploy-redis.sh

# Deploy other components
./deploy-airflow-storage.sh
./deploy-airflow-vault-integration.sh
./deploy-airflow-rbac.sh
./deploy-airflow-ingress.sh
```

All scripts will now correctly create the airflow namespace and RBAC configuration before deploying their respective components.