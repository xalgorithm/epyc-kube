# WordPress on Kubernetes (kampfzwerg namespace)

WordPress deployment with Nginx + PHP-FPM architecture for improved performance and security.

## Architecture

- **Web Server**: Nginx 1.25
- **PHP Runtime**: PHP-FPM (WordPress 6.4.3)
- **Database**: MySQL 8.0
- **Cache**: Memcached 1.6
- **Storage**: NFS-backed persistent volumes
- **TLS**: Let's Encrypt via cert-manager
- **Ingress**: Traefik

## Quick Start

### Prerequisites

1. Kubernetes cluster with k3s
2. NFS storage provider configured
3. cert-manager installed
4. Traefik ingress controller

### Deploy

```bash
# Create namespace and apply all resources
kubectl apply -f wordpress-complete.yaml

# Create database credentials secret
kubectl create secret generic wordpress-db-credentials \
  -n kampfzwerg \
  --from-literal=db_password='YOUR_SECURE_PASSWORD'

# Initialize WordPress files (if fresh install)
kubectl apply -f wordpress-init-job.yaml

# Wait for deployment
kubectl rollout status deployment/wordpress -n kampfzwerg
kubectl rollout status deployment/wordpress-mysql -n kampfzwerg
```

### Access

- **URL**: https://kampfzwerg.gray-beard.com
- **Admin**: https://kampfzwerg.gray-beard.com/wp-admin

## Architecture Details

### WordPress Pod

The WordPress pod runs two containers in a sidecar pattern:

1. **Nginx Container**: Handles HTTP requests, serves static files
2. **PHP-FPM Container**: Processes PHP via FastCGI on port 9000

Both containers share the same persistent volume for WordPress files.

### Init Container

A Debian-based init container runs before the main containers to set proper file permissions:
- Ownership: `www-data:www-data` (UID/GID 33)
- Directories: 755
- Files: 644
- wp-content: 775 (for uploads and updates)

### Persistent Storage

- **wordpress-data**: 10Gi for WordPress files (/var/www/html)
- **mysql-data**: 10Gi for MySQL database (/var/lib/mysql)

### Memcached

Object caching layer for WordPress to reduce database load:
- Memory limit: 256MB
- Max object size: 5MB
- Network policy restricts access to WordPress pods only

## Configuration

### PHP Settings

Located in `php-fpm-config` ConfigMap:

- `upload_max_filesize`: 20M
- `post_max_size`: 25M
- `memory_limit`: 256M
- `max_execution_time`: 300s
- `max_input_vars`: 3000

### Nginx Settings

Located in `nginx-config` ConfigMap:

- `client_max_body_size`: 20M
- FastCGI timeout: 300s
- Static file caching enabled
- PHP file upload protection

### Database Configuration

MySQL 8.0 with:
- Database: `wordpress`
- User: `wordpress`
- Password: From secret `wordpress-db-credentials`

## Monitoring

WordPress exporter for Prometheus metrics is available in `wordpress-exporter.yaml` (optional).

## Maintenance

### Scaling

```bash
# Scale WordPress pods (if using shared storage)
kubectl scale deployment wordpress -n kampfzwerg --replicas=2
```

### Updates

```bash
# Update WordPress image
kubectl set image deployment/wordpress \
  -n kampfzwerg \
  php-fpm=wordpress:6.5-fpm

# Restart deployment
kubectl rollout restart deployment/wordpress -n kampfzwerg
```

### Backup

Use standard Kubernetes backup tools for PVCs, or implement database backups:

```bash
# Database backup example
kubectl exec -n kampfzwerg deployment/wordpress-mysql -- \
  mysqldump -u wordpress -p wordpress > backup.sql
```

### Troubleshooting

```bash
# Check pod status
kubectl get pods -n kampfzwerg

# View logs
kubectl logs -n kampfzwerg deployment/wordpress -c nginx
kubectl logs -n kampfzwerg deployment/wordpress -c php-fpm

# Check init container logs
kubectl logs -n kampfzwerg <pod-name> -c fix-permissions

# Exec into containers
kubectl exec -it -n kampfzwerg deployment/wordpress -c nginx -- sh
kubectl exec -it -n kampfzwerg deployment/wordpress -c php-fpm -- bash

# Test WordPress database connection
kubectl exec -n kampfzwerg deployment/wordpress-mysql -- \
  mysql -u wordpress -p -e "SHOW DATABASES;"
```

## Security

- TLS certificates automatically managed by cert-manager
- Network policies restrict Memcached access
- PHP file uploads blocked in uploads directory
- Hidden files (.htaccess, etc.) blocked by Nginx
- Database credentials stored in Kubernetes secrets

## Performance Tuning

### PHP-FPM

Adjust worker processes in `php-fpm-config`:
- `pm.max_children`: Maximum worker processes
- `pm.start_servers`: Initial workers
- `pm.max_requests`: Workers recycled after N requests

### Memcached

Increase cache size if needed:
```bash
kubectl set env deployment/memcached -n kampfzwerg MEMCACHED_MEMORY=512
```

### MySQL

For production, consider:
- Dedicated MySQL instance outside Kubernetes
- Read replicas for scaling
- Regular optimization and indexing

## Files

- `wordpress-complete.yaml`: Complete deployment (all-in-one)
- `wordpress-init-job.yaml`: One-time job to initialize WordPress files
- `wordpress-exporter.yaml`: Optional Prometheus exporter
- `README.md`: This file

## Notes

- The PHP-FPM entrypoint is overridden with `command: ["php-fpm"]` to prevent automatic file copying
- WordPress files must be initialized once using the init job or manual copy
- The wp-config.php file must include proxy header trust for HTTPS detection behind Traefik
- Site URLs are set via WORDPRESS_CONFIG_EXTRA environment variable

## Migration from Apache

This deployment migrated from Apache to Nginx + PHP-FPM for:
- Better performance (separate static file serving)
- Lower memory footprint
- More granular resource management
- Industry best practices for PHP applications

The migration maintained all WordPress content, database, and configurations.
