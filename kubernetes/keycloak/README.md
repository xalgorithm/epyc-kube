# Keycloak Single Sign-On (SSO) Setup

> 📚 **Navigation:** [Main README](../../README.md) | [Documentation Index](../../docs/README.md) | [Vault](../vault/README.md)

This directory contains scripts and configuration files for setting up Keycloak as a Single Sign-On (SSO) provider for applications in the Kubernetes cluster.

**Related Documentation:**
- [Main README](../../README.md) - Platform capabilities
- [Vault Setup](../vault/README.md) - Secrets management
- [Grafana SSO](../grafana/README.md) - Grafana integration

## Overview

The setup consists of:
- Keycloak deployment in its own namespace
- Integration with the following applications:
  - Grafana
  - n8n
  - WordPress

## Prerequisites

- Kubernetes cluster with kubectl access
- Keycloak installed and accessible at https://login.gray-beard.com
- Applications (Grafana, n8n, WordPress) installed and running
- Vault (optional) for secure credential storage

## Initial Keycloak Deployment

The initial Keycloak deployment was set up using the `deploy-keycloak.sh` script which:
- Creates a dedicated namespace
- Deploys PostgreSQL database
- Deploys Keycloak server
- Sets up TLS using Let's Encrypt certificates
- Configures Ingress for external access

## SSO Configuration

The SSO configuration is handled by three separate scripts:

### 1. Grafana SSO Setup

```bash
./configure-grafana-sso.sh
```

This script:
- Creates a Keycloak realm (`xalg-apps`) if it doesn't exist
- Creates/updates a Keycloak client for Grafana
- Configures Grafana to use Keycloak for authentication
- Restarts the Grafana deployment to apply changes

### 2. n8n SSO Setup

```bash
./configure-n8n-sso.sh
```

This script:
- Creates a Keycloak realm (`xalg-apps`) if it doesn't exist
- Creates/updates a Keycloak client for n8n
- Creates a Kubernetes secret with OIDC configuration
- Updates the n8n deployment to use the OIDC configuration
- Restarts the n8n deployment to apply changes

### 3. WordPress SSO Setup

```bash
./configure-wordpress-sso.sh
```

This script:
- Creates a Keycloak realm (`xalg-apps`) if it doesn't exist
- Creates/updates a Keycloak client for WordPress
- Creates a Kubernetes secret with OIDC configuration
- Creates a ConfigMap with plugin installation instructions
- Note: Requires manual installation of the OpenID Connect Generic plugin in WordPress

## Credential Storage

All SSO client secrets are stored in:
1. Kubernetes secrets in each application's namespace
2. HashiCorp Vault (if available) under `secret/[app-name]-sso`

## Testing the SSO Setup

A test user with the following credentials is created:
- Username: testuser
- Password: testpassword
- Email: testuser@example.com

## Application Access

- Keycloak: https://login.gray-beard.com
- Grafana: https://grafana.gray-beard.com
- n8n: https://automate.gray-beard.com
- WordPress: https://blog.gray-beard.com

## Troubleshooting

If you encounter issues with the SSO setup:

1. Check that Keycloak is running:
   ```bash
   kubectl get pods -n keycloak
   ```

2. Verify that the applications are running:
   ```bash
   kubectl get pods -n monitoring  # For Grafana
   kubectl get pods -n n8n         # For n8n
   kubectl get pods -n wordpress   # For WordPress
   ```

3. Check the Keycloak logs:
   ```bash
   kubectl logs -n keycloak deployment/keycloak
   ```

4. Check application logs for SSO-related errors:
   ```bash
   kubectl logs -n monitoring deployment/[grafana-deployment-name]
   kubectl logs -n n8n deployment/n8n
   kubectl logs -n wordpress deployment/wordpress
   ```

5. Verify that the SSO client configurations exist in Keycloak:
   - Open https://login.gray-beard.com
   - Log in with admin credentials
   - Navigate to "Clients" in the left sidebar
   - Check that clients for Grafana, n8n, and WordPress exist

## Cleanup

To remove the SSO configuration:

1. Delete the Keycloak clients
2. Remove the SSO configuration from each application
3. Restart the applications 