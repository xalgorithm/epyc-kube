# WordPress Domain Migration Guide

This guide details the process of migrating your WordPress site from `metaphysicalninja.com` to `kampfzwerg.gray-beard.com`.

## Prerequisites

Before starting the migration, ensure:

1. You have ownership of the `kampfzwerg.gray-beard.com` domain
2. You have access to the domain's DNS settings
3. Your Kubernetes cluster is running and accessible
4. You have kubectl configured to access your cluster

## Migration Process

### 1. DNS Configuration

Update your DNS records to point `kampfzwerg.gray-beard.com` to the same IP address as `metaphysicalninja.com`:

```bash
# Find your current WordPress ingress IP
kubectl get ingress -n wordpress wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create an A record for `kampfzwerg.gray-beard.com` pointing to this IP address in your domain registrar or DNS provider's control panel.

### 2. Update Kubernetes Configurations

The following files have been updated to use the new domain:

- `ingress.yaml` - Updated host and TLS settings
- `wordpress-deployment.yaml` - Updated WordPress site URL configuration
- `deployment.yaml` - Updated WordPress site URL configuration

### 3. Apply Changes

We've created a script to handle the migration safely:

```bash
# Run the domain migration script
./update-domain.sh
```

This script will:
- Update the Kubernetes ingress configuration
- Patch the WordPress deployment with the new domain
- Update all URLs in the WordPress database
- Restart the WordPress pod

### 4. Verify Configuration

To verify the DNS configuration and site accessibility:

```bash
# Run the verification script
./verify-domain.sh
```

### 5. SSL Certificate

The Let's Encrypt certificate for `kampfzwerg.gray-beard.com` will be automatically requested and configured by cert-manager when the ingress is updated. It may take a few minutes for the certificate to be issued and become valid.

To check the certificate status:

```bash
kubectl get certificate -n wordpress
```

### 6. WordPress Database Updates

The migration script uses WordPress CLI to update URLs in the database. However, some URLs might be stored in serialized data and may require additional updates.

If you notice any issues with links or images still pointing to the old domain, you may need to:

1. Log into WordPress admin at `https://kampfzwerg.gray-beard.com/wp-admin`
2. Install a plugin like "Better Search Replace" to handle serialized data
3. Run a search and replace for any remaining references to `metaphysicalninja.com`

### 7. Troubleshooting

If you encounter issues:

#### Certificate Problems
```bash
# Check certificate status
kubectl get certificate -n wordpress
kubectl describe certificate wordpress-tls -n wordpress

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

#### WordPress Accessibility Issues
```bash
# Check WordPress pod status
kubectl get pods -n wordpress
kubectl describe pod -n wordpress $(kubectl get pods -n wordpress -l app=wordpress -o jsonpath="{.items[0].metadata.name}")

# Check WordPress pod logs
kubectl logs -n wordpress $(kubectl get pods -n wordpress -l app=wordpress -o jsonpath="{.items[0].metadata.name}")
```

#### Database URL Updates
If URLs in the database weren't updated correctly:
```bash
# Run the updates manually
kubectl exec -n wordpress $(kubectl get pods -n wordpress -l app=wordpress -o jsonpath="{.items[0].metadata.name}") -- wp search-replace 'https://metaphysicalninja.com' 'https://kampfzwerg.gray-beard.com' --all-tables
kubectl exec -n wordpress $(kubectl get pods -n wordpress -l app=wordpress -o jsonpath="{.items[0].metadata.name}") -- wp search-replace 'http://metaphysicalninja.com' 'https://kampfzwerg.gray-beard.com' --all-tables
```

### 8. Finalize Migration

After confirming everything works correctly:

1. Update any external references to your site (social media, email signatures, etc.)
2. Consider setting up a redirect from the old domain to the new one
3. Update any backups or monitoring to use the new domain name

## Rollback Plan

If you need to revert the changes:

1. Run the provided rollback script:
```bash
./rollback-domain.sh
```

This will restore the original domain configuration. 