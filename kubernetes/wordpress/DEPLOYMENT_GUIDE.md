# WordPress Deployment Guide

## Quick Reference

**Namespace:** `kampfzwerg`  
**Domain:** https://kampfzwerg.gray-beard.com  
**Admin:** https://kampfzwerg.gray-beard.com/wp-admin

## Files Overview

| File | Purpose |
|------|---------|
| `wordpress-complete.yaml` | **Main deployment file** - All resources needed for WordPress |
| `wordpress-init-job.yaml` | One-time job to initialize WordPress files (fresh installs) |
| `wordpress-exporter.yaml` | Optional Prometheus metrics exporter |
| `wordpress-dashboard.yaml` | Grafana dashboard configuration |
| `README.md` | Complete documentation |

## Deployment Steps

### 1. Fresh Installation

```bash
# Create the namespace and all resources
kubectl apply -f wordpress-complete.yaml

# Create database credentials
kubectl create secret generic wordpress-db-credentials \
  -n kampfzwerg \
  --from-literal=db_password='YOUR_SECURE_PASSWORD'

# Initialize WordPress files
kubectl apply -f wordpress-init-job.yaml

# Wait for completion
kubectl wait --for=condition=complete job/wordpress-init -n kampfzwerg --timeout=10m

# Check status
kubectl get pods -n kampfzwerg
```

### 2. Existing Installation (Migration)

If you already have WordPress files and database:

```bash
# Apply resources (skip init job)
kubectl apply -f wordpress-complete.yaml

# Create credentials with existing password
kubectl create secret generic wordpress-db-credentials \
  -n kampfzwerg \
  --from-literal=db_password='YOUR_EXISTING_PASSWORD'

# Restore database
kubectl exec -i -n kampfzwerg deployment/wordpress-mysql -- \
  mysql -u wordpress -p wordpress < backup.sql

# Copy WordPress files to PVC manually if needed
```

### 3. Add Monitoring (Optional)

```bash
# Deploy Prometheus exporter
kubectl apply -f wordpress-exporter.yaml

# Import Grafana dashboard
kubectl apply -f wordpress-dashboard.yaml
```

## Verification

```bash
# Check all pods are running
kubectl get pods -n kampfzwerg

# Expected output:
# NAME                               READY   STATUS    RESTARTS   AGE
# memcached-xxx                      1/1     Running   0          5m
# wordpress-xxx                      2/2     Running   0          5m
# wordpress-mysql-xxx                1/1     Running   0          5m

# Test WordPress
curl -sI https://kampfzwerg.gray-beard.com | head -1
# Expected: HTTP/2 200
```

## Common Tasks

### Update WordPress

```bash
# Update to new version
kubectl set image deployment/wordpress \
  -n kampfzwerg \
  php-fpm=wordpress:6.5-fpm

# Restart
kubectl rollout restart deployment/wordpress -n kampfzwerg
```

### Scale WordPress

```bash
# Increase replicas (requires ReadWriteMany storage or split setup)
kubectl scale deployment wordpress -n kampfzwerg --replicas=2
```

### Database Backup

```bash
# Export database
kubectl exec -n kampfzwerg deployment/wordpress-mysql -- \
  mysqldump -u wordpress -p'PASSWORD' wordpress > backup_$(date +%Y%m%d).sql

# Import database
kubectl exec -i -n kampfzwerg deployment/wordpress-mysql -- \
  mysql -u wordpress -p'PASSWORD' wordpress < backup.sql
```

### View Logs

```bash
# Nginx logs
kubectl logs -n kampfzwerg deployment/wordpress -c nginx -f

# PHP-FPM logs
kubectl logs -n kampfzwerg deployment/wordpress -c php-fpm -f

# MySQL logs
kubectl logs -n kampfzwerg deployment/wordpress-mysql -f
```

### Access Shell

```bash
# WordPress container
kubectl exec -it -n kampfzwerg deployment/wordpress -c php-fpm -- bash

# Database
kubectl exec -it -n kampfzwerg deployment/wordpress-mysql -- mysql -u wordpress -p wordpress
```

## Architecture Notes

### Container Structure

The WordPress pod runs two containers:

1. **nginx**: Web server (port 80)
   - Serves static files
   - Proxies PHP requests to php-fpm via 127.0.0.1:9000

2. **php-fpm**: PHP processor (port 9000)
   - Processes PHP code
   - Shares volume with nginx
   - Entrypoint overridden to prevent file copying

### Storage

- **wordpress-data**: 10Gi PVC for WordPress files
- **mysql-data**: 10Gi PVC for MySQL database
- Both use NFS storage class

### Important Configuration

The wp-config.php must include proxy header trust:

```php
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
```

This is required for WordPress to detect HTTPS when behind Traefik ingress.

## Troubleshooting

### Pod not starting

```bash
# Check pod events
kubectl describe pod -n kampfzwerg <pod-name>

# Check init container logs
kubectl logs -n kampfzwerg <pod-name> -c fix-permissions
```

### 403 Forbidden

- Check file permissions (should be www-data:www-data)
- Verify index.php exists in /var/www/html

### 502 Bad Gateway

- Check PHP-FPM is running: `kubectl logs -n kampfzwerg deployment/wordpress -c php-fpm`
- Verify PHP-FPM listening on 127.0.0.1:9000

### Database connection issues

```bash
# Test MySQL connectivity
kubectl exec -n kampfzwerg deployment/wordpress-mysql -- \
  mysqladmin ping -u wordpress -p'PASSWORD'

# Check if database exists
kubectl exec -n kampfzwerg deployment/wordpress-mysql -- \
  mysql -u wordpress -p'PASSWORD' -e "SHOW DATABASES;"
```

### Redirect loops

- Ensure wp-config.php has proxy header trust
- Check WP_HOME and WP_SITEURL are correct in database:
  ```bash
  kubectl exec -n kampfzwerg deployment/wordpress-mysql -- \
    mysql -u wordpress -p'PASSWORD' wordpress \
    -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('siteurl', 'home');"
  ```

## Cleanup

```bash
# Delete everything
kubectl delete namespace kampfzwerg

# This will also delete PVCs and all data!
```

## Migration History

This deployment was migrated from:
- **Old namespace:** `wordpress`
- **Old architecture:** Apache + mod_php
- **New architecture:** Nginx + PHP-FPM
- **Benefits:** Better performance, lower memory, separate containers

Migration completed: 2025-09-30
