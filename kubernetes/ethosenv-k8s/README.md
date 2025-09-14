# WordPress Kubernetes Deployment

This directory contains the Kubernetes manifests and scripts to deploy the WordPress application from the `ethosenv` Docker Compose setup to a Kubernetes cluster.

## Overview

The deployment includes:
- **MySQL 8.0** database with persistent storage
- **WordPress** application with persistent storage
- **SSL Certificate** automatically managed by cert-manager and Let's Encrypt
- **Ingress** configuration with SSL termination for ethos.gray-beard.com
- **Secrets** management for sensitive data
- **Migration scripts** to transfer existing content and database

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Ingress       │    │   WordPress     │
│   (External)    │───▶│   Deployment    │
└─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   MySQL         │
                       │   Deployment    │
                       └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   Persistent    │
                       │   Storage       │
                       └─────────────────┘
```

## Files Structure

```
kubernetes/ethosenv-k8s/
├── 01-namespace.yaml              # Namespace definition
├── 02-secrets.yaml                # WordPress and MySQL secrets
├── 03-storage.yaml                # Persistent Volume Claims
├── 04-mysql-deployment.yaml       # MySQL database deployment
├── 05-wordpress-deployment.yaml   # WordPress application deployment
├── 06-ingress.yaml                # Ingress configuration with SSL
├── 07-cert-manager-issuer.yaml    # cert-manager ClusterIssuer for Let's Encrypt
├── 08-ssl-certificate.yaml        # SSL Certificate for ethos.gray-beard.com
├── deploy-wordpress.sh            # Main deployment script
├── install-cert-manager.sh        # cert-manager installation script
├── check-ssl-status.sh            # SSL certificate status checker
├── migrate-wordpress-content.sh   # Content migration script
├── migrate-database.sh            # Database migration script
├── monitor-wordpress.sh           # Monitoring script
└── README.md                      # This file
```

## Prerequisites

1. **Kubernetes Cluster**: Running Kubernetes cluster with kubectl access
2. **Storage Class**: Available storage class (defaults to `nfs-client`)
3. **Ingress Controller**: Nginx ingress controller (or modify ingress.yaml)
4. **DNS Configuration**: ethos.gray-beard.com should point to your ingress controller IP
5. **cert-manager** (optional): Will be installed automatically if not present
6. **Docker** (optional): For database backup from existing setup

## Quick Start

### 1. Deploy WordPress to Kubernetes

```bash
# Deploy all components
./deploy-wordpress.sh
```

### 2. Migrate Existing Content

```bash
# Migrate WordPress files
./migrate-wordpress-content.sh

# Migrate database (full migration)
./migrate-database.sh full-migration
```

### 3. Access WordPress

```bash
# Port forward for local access
kubectl port-forward svc/wordpress 8080:80 -n ethosenv

# Production access (requires DNS configuration)
# Ensure ethos.gray-beard.com points to your ingress IP
# Then visit: https://ethos.gray-beard.com
```

## Detailed Deployment Steps

### Step 1: Review Configuration

Before deployment, review and customize:

1. **Secrets** (`02-secrets.yaml`):
   - Update database passwords
   - Generate new WordPress security keys
   - Use proper secret management in production

2. **Storage** (`03-storage.yaml`):
   - Adjust storage class if needed
   - Modify storage sizes based on requirements

3. **Ingress** (`06-ingress.yaml`):
   - Update hostname
   - Configure SSL/TLS certificates
   - Adjust ingress controller annotations

### Step 2: Deploy Infrastructure

```bash
# Create namespace
kubectl apply -f 01-namespace.yaml

# Create secrets
kubectl apply -f 02-secrets.yaml

# Create storage
kubectl apply -f 03-storage.yaml

# Wait for PVCs to be bound
kubectl get pvc -n ethosenv -w
```

### Step 3: Deploy Database

```bash
# Deploy MySQL
kubectl apply -f 04-mysql-deployment.yaml

# Wait for MySQL to be ready
kubectl wait --for=condition=available --timeout=300s deployment/mysql -n ethosenv
```

### Step 4: Deploy WordPress

```bash
# Deploy WordPress
kubectl apply -f 05-wordpress-deployment.yaml

# Wait for WordPress to be ready
kubectl wait --for=condition=available --timeout=300s deployment/wordpress -n ethosenv
```

### Step 5: Configure SSL Certificates

```bash
# Install cert-manager (if not already installed)
./install-cert-manager.sh

# Create SSL certificate
kubectl apply -f 08-ssl-certificate.yaml

# Check certificate status
./check-ssl-status.sh
```

### Step 6: Configure External Access

```bash
# Create ingress with SSL
kubectl apply -f 06-ingress.yaml

# Get ingress IP
kubectl get ingress -n ethosenv
```

## Migration from Docker Compose

### Content Migration

The existing WordPress files need to be copied to the Kubernetes deployment:

```bash
# Migrate WordPress files and themes
./migrate-wordpress-content.sh
```

This script:
- Creates an archive of the existing WordPress directory
- Copies it to the WordPress pod
- Extracts files with proper permissions
- Preserves the Kubernetes-compatible wp-config.php

### Database Migration

Migrate the existing MySQL database:

```bash
# Option 1: Full automatic migration
./migrate-database.sh full-migration

# Option 2: Step-by-step migration
./migrate-database.sh backup
./migrate-database.sh restore
./migrate-database.sh update-urls http://localhost:8080 http://wordpress.local
```

The database migration:
- Creates a backup from the existing Docker setup
- Restores the backup to the Kubernetes MySQL instance
- Updates WordPress URLs to match the new deployment

## SSL Certificate Management

### Automatic Certificate Issuance

The deployment uses cert-manager with Let's Encrypt to automatically issue and renew SSL certificates:

- **Domain**: ethos.gray-beard.com
- **Certificate Authority**: Let's Encrypt (production)
- **Renewal**: Automatic (30 days before expiry)
- **Challenge Type**: HTTP-01 (via ingress)

### Certificate Status Commands

```bash
# Check overall SSL status
./check-ssl-status.sh

# Check certificate resource
kubectl describe certificate ethos-ssl-cert -n ethosenv

# Check TLS secret
kubectl describe secret ethos-tls-secret -n ethosenv

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

### Troubleshooting SSL Issues

1. **Certificate Pending**: Wait 5-10 minutes for Let's Encrypt validation
2. **DNS Issues**: Ensure ethos.gray-beard.com points to your ingress IP
3. **Firewall**: Ensure port 80 is accessible for HTTP-01 challenge
4. **Rate Limits**: Let's Encrypt has rate limits; use staging issuer for testing

## Configuration

### Environment Variables

WordPress configuration is managed through Kubernetes secrets:

- `WORDPRESS_DB_HOST`: MySQL service hostname
- `WORDPRESS_DB_USER`: Database username
- `WORDPRESS_DB_PASSWORD`: Database password
- `WORDPRESS_DB_NAME`: Database name
- WordPress security keys and salts

### Persistent Storage

Two persistent volumes are created:
- **MySQL Data**: 10Gi for database storage
- **WordPress Files**: 5Gi for WordPress content

### Security

Security features implemented:
- Non-root containers where possible
- Security contexts with appropriate user/group IDs
- Secrets for sensitive data
- Network policies (can be added)

## Monitoring and Maintenance

### Check Deployment Status

```bash
# Check all resources
kubectl get all -n ethosenv

# Check persistent volumes
kubectl get pvc -n ethosenv

# Check pod logs
kubectl logs -f deployment/wordpress -n ethosenv
kubectl logs -f deployment/mysql -n ethosenv
```

### Database Backup

```bash
# Create database backup
kubectl exec -n ethosenv deployment/mysql -- mysqldump -u root -proot_password wordpress > backup.sql

# Restore from backup
kubectl exec -i -n ethosenv deployment/mysql -- mysql -u root -proot_password wordpress < backup.sql
```

### Scaling

```bash
# Scale WordPress (MySQL should remain at 1 replica)
kubectl scale deployment wordpress --replicas=3 -n ethosenv
```

## Troubleshooting

### Common Issues

1. **PVC Not Binding**:
   ```bash
   kubectl describe pvc -n ethosenv
   # Check storage class availability
   kubectl get storageclass
   ```

2. **Database Connection Issues**:
   ```bash
   # Check MySQL pod logs
   kubectl logs deployment/mysql -n ethosenv
   
   # Test database connection
   kubectl exec -it deployment/mysql -n ethosenv -- mysql -u root -proot_password
   ```

3. **WordPress Not Loading**:
   ```bash
   # Check WordPress pod logs
   kubectl logs deployment/wordpress -n ethosenv
   
   # Check file permissions
   kubectl exec -it deployment/wordpress -n ethosenv -- ls -la /var/www/html
   ```

### Debug Commands

```bash
# Get pod shell access
kubectl exec -it deployment/wordpress -n ethosenv -- bash
kubectl exec -it deployment/mysql -n ethosenv -- bash

# Check service connectivity
kubectl exec -it deployment/wordpress -n ethosenv -- nslookup mysql

# Check ingress status
kubectl describe ingress wordpress-ingress -n ethosenv
```

## Production Considerations

### Security Hardening

1. **Update Secrets**: Generate strong, unique passwords and keys
2. **SSL/TLS**: Configure proper SSL certificates
3. **Network Policies**: Implement network segmentation
4. **RBAC**: Set up proper role-based access control

### Performance Optimization

1. **Resource Limits**: Adjust CPU and memory limits based on load
2. **Horizontal Scaling**: Scale WordPress pods based on traffic
3. **Database Optimization**: Tune MySQL configuration
4. **Caching**: Implement Redis or Memcached

### Backup Strategy

1. **Database Backups**: Set up automated database backups
2. **File Backups**: Backup WordPress files and uploads
3. **Disaster Recovery**: Test restore procedures

### Monitoring

1. **Health Checks**: Configure proper liveness and readiness probes
2. **Metrics**: Set up Prometheus monitoring
3. **Logging**: Centralize logs with ELK stack or similar
4. **Alerting**: Configure alerts for critical issues

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review Kubernetes and WordPress documentation
3. Check pod logs for specific error messages
4. Verify network connectivity and DNS resolution