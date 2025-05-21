# WordPress Kubernetes Configuration

This directory contains the Kubernetes manifest files for deploying WordPress on Kubernetes.

## Files

- **deployment.yaml**: Main WordPress deployment configuration with init container for fixing permissions
- **backup.yaml**: CronJob for automatically backing up the WordPress database and files
- **fix-permissions-job.yaml**: Job for manually fixing permissions on WordPress files
- **ingress.yaml**: Ingress configuration for WordPress with HTTPS support
- **cert-issuer.yaml**: Let's Encrypt production ClusterIssuer for SSL certificates
- **https-redirect.yaml**: Traefik middleware for redirecting HTTP traffic to HTTPS

## Usage

To apply all configurations:

```bash
kubectl apply -f kubernetes/wordpress/
```

Or apply individual files as needed:

```bash
kubectl apply -f kubernetes/wordpress/deployment.yaml
kubectl apply -f kubernetes/wordpress/ingress.yaml
```

## Notes

- WordPress requires proper file permissions to be able to self-update and install plugins
- The deployment includes an init container that sets the correct permissions on startup
- Automatic backups are configured to run daily at 2 AM
- HTTPS is enabled with Let's Encrypt certificates 