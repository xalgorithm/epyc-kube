# Activepieces on Kubernetes

> 📚 **Navigation:** [Main README](../../README.md) | [Documentation Index](../../docs/README.md) | [n8n](../n8n/)

Activepieces is an open-source automation platform (alternative to Zapier/Make.com) deployed in the `automation` namespace.

**Related Documentation:**
- [Main README](../../README.md) - Platform overview
- [n8n Automation](../n8n/) - Alternative workflow platform
- [Keycloak SSO](../keycloak/README.md) - Authentication setup

## Quick Reference

- **Namespace:** `automation`
- **Domain:** https://automate2.gray-beard.com
- **Image:** activepieces/activepieces:latest

## Architecture

- **Database:** PostgreSQL 14 (10Gi storage)
- **Cache/Queue:** Redis 7 (5Gi storage)
- **Application:** Activepieces (unsandboxed execution mode)
- **Ingress:** Traefik with Let's Encrypt TLS

## Deployment

### 1. Generate Secrets

First, generate strong random secrets:

```bash
# Generate encryption key (32 characters)
openssl rand -base64 32

# Generate JWT secret (32 characters)
openssl rand -base64 32

# Generate database password
openssl rand -base64 24
```

### 2. Update Secrets

Edit `activepieces-complete.yaml` and replace the following values in the secrets section:

```yaml
stringData:
  AP_ENCRYPTION_KEY: "<your-generated-encryption-key>"
  AP_JWT_SECRET: "<your-generated-jwt-secret>"
  POSTGRES_PASSWORD: "<your-generated-db-password>"
```

### 3. Deploy

```bash
# Deploy all resources
kubectl apply -f activepieces-complete.yaml

# Wait for deployment
kubectl rollout status deployment/postgres -n automation
kubectl rollout status deployment/redis -n automation
kubectl rollout status deployment/activepieces -n automation
```

### 4. Verify

```bash
# Check all pods are running
kubectl get pods -n automation

# Expected output:
# NAME                           READY   STATUS    RESTARTS   AGE
# activepieces-xxx               1/1     Running   0          5m
# postgres-xxx                   1/1     Running   0          5m
# redis-xxx                      1/1     Running   0          5m

# Check ingress
kubectl get ingress -n automation

# Test access
curl -I https://automate2.gray-beard.com
```

## Initial Setup

1. Navigate to https://automate2.gray-beard.com
2. Create your admin account (first user becomes admin)
3. Start creating automation flows!

## Configuration

### Environment Variables

Key configuration in the deployment:

- `AP_FRONTEND_URL`: https://automate2.gray-beard.com
- `AP_API_URL`: https://automate2.gray-beard.com
- `AP_ENVIRONMENT`: prod
- `AP_EXECUTION_MODE`: UNSANDBOXED (allows code execution)
- `AP_SIGN_UP_ENABLED`: true (allows user registration)
- `AP_QUEUE_MODE`: REDIS
- `AP_TRIGGER_DEFAULT_POLL_INTERVAL`: 5 minutes

### Database

- PostgreSQL 14
- Database: activepieces
- User: activepieces
- Storage: 10Gi NFS-backed PVC

### Redis

- Redis 7 with persistence
- Appendonly mode enabled
- Snapshot: every 60 seconds if 1+ keys changed
- Storage: 5Gi NFS-backed PVC

## Maintenance

### View Logs

```bash
# Activepieces logs
kubectl logs -n automation deployment/activepieces -f

# PostgreSQL logs
kubectl logs -n automation deployment/postgres -f

# Redis logs
kubectl logs -n automation deployment/redis -f
```

### Restart Components

```bash
# Restart Activepieces
kubectl rollout restart deployment/activepieces -n automation

# Restart PostgreSQL (will cause brief downtime)
kubectl rollout restart deployment/postgres -n automation

# Restart Redis
kubectl rollout restart deployment/redis -n automation
```

### Access Database

```bash
# Connect to PostgreSQL
kubectl exec -it -n automation deployment/postgres -- psql -U activepieces -d activepieces

# Common queries:
# List tables: \dt
# List users: SELECT * FROM "user";
# Exit: \q
```

### Access Redis

```bash
# Connect to Redis CLI
kubectl exec -it -n automation deployment/redis -- redis-cli

# Common commands:
# Check connection: PING
# List keys: KEYS *
# Get key: GET <key>
# Exit: exit
```

### Database Backup

```bash
# Backup database
kubectl exec -n automation deployment/postgres -- \
  pg_dump -U activepieces activepieces > activepieces_backup_$(date +%Y%m%d).sql

# Restore database
kubectl exec -i -n automation deployment/postgres -- \
  psql -U activepieces activepieces < activepieces_backup.sql
```

### Scale Activepieces

```bash
# Increase replicas (requires session management consideration)
kubectl scale deployment activepieces -n automation --replicas=2

# Note: For multi-replica setups, ensure proper session handling
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -n automation <pod-name>

# Check logs
kubectl logs -n automation <pod-name>
```

### Database Connection Issues

```bash
# Test PostgreSQL connectivity
kubectl exec -n automation deployment/postgres -- \
  pg_isready -U activepieces

# Check PostgreSQL is listening
kubectl exec -n automation deployment/postgres -- \
  netstat -tlnp | grep 5432
```

### Redis Connection Issues

```bash
# Test Redis connectivity
kubectl exec -n automation deployment/redis -- redis-cli ping

# Check Redis is listening
kubectl exec -n automation deployment/redis -- \
  netstat -tlnp | grep 6379
```

### Cannot Access Web Interface

1. Check ingress is configured:
   ```bash
   kubectl get ingress -n automation
   ```

2. Verify TLS certificate is ready:
   ```bash
   kubectl get certificate -n automation
   ```

3. Check DNS points to your cluster:
   ```bash
   nslookup automate2.gray-beard.com
   ```

4. Test direct service access:
   ```bash
   kubectl port-forward -n automation svc/activepieces 8080:80
   # Then access http://localhost:8080
   ```

### 500 Internal Server Error

- Check Activepieces logs for errors
- Verify database is accessible
- Verify Redis is accessible
- Check encryption key and JWT secret are set correctly

## Upgrade

```bash
# Update to latest version
kubectl set image deployment/activepieces \
  -n automation \
  activepieces=activepieces/activepieces:latest

# Or edit the YAML and reapply
kubectl apply -f activepieces-complete.yaml
```

## Security Notes

1. **Change all default secrets** before deploying to production
2. **Encryption key** is used for sensitive data - keep it secure and backed up
3. **JWT secret** is used for authentication tokens
4. **Database password** should be strong and unique
5. Consider **disabling sign-ups** (`AP_SIGN_UP_ENABLED=false`) after creating admin account
6. Use **network policies** to restrict access between namespaces if needed

## Resource Requirements

**Minimum:**
- CPU: 600m (250m postgres + 100m redis + 250m activepieces)
- Memory: 896Mi (256Mi postgres + 128Mi redis + 512Mi activepieces)
- Storage: 15Gi (10Gi postgres + 5Gi redis)

**Recommended for Production:**
- CPU: 2000m (500m postgres + 200m redis + 1000m activepieces + overhead)
- Memory: 2Gi (512Mi postgres + 256Mi redis + 1Gi activepieces + overhead)
- Storage: 50Gi+ (20Gi postgres + 10Gi redis + buffer)

## Features

- Visual flow builder
- 200+ integrations and growing
- Webhooks support
- Scheduled triggers
- API access
- Team collaboration
- Self-hosted
- Open source

## Useful Links

- [Activepieces Documentation](https://www.activepieces.com/docs)
- [GitHub Repository](https://github.com/activepieces/activepieces)
- [Community Forum](https://community.activepieces.com/)

## Cleanup

```bash
# Delete everything
kubectl delete namespace automation

# This will delete all resources and data
```

## Files

- `activepieces-complete.yaml`: Complete deployment manifest
- `README.md`: This documentation

## Notes

- Execution mode is set to `UNSANDBOXED` which allows code execution
- Telemetry is disabled for privacy
- Templates are sourced from official Activepieces cloud
- Default polling interval for triggers is 5 minutes
- Sign-up is enabled by default - disable after creating admin

