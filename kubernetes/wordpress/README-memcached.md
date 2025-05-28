# Secure Memcached for WordPress

## Overview

This setup deploys a Memcached instance for WordPress with enhanced security. The Memcached service is only accessible to WordPress pods within the `wordpress` namespace, enforced by Kubernetes NetworkPolicy.

The implementation provides:

1. Fast object caching for WordPress using Memcached
2. Restricted access to Memcached with network policies
3. Simple deployment and testing scripts
4. WordPress plugin for Memcached integration

## Components

### 1. Memcached Deployment

- `memcached-deployment.yaml`: Deploys Memcached server with NetworkPolicy
- The NetworkPolicy restricts access to only pods with the `app: wordpress` label
- Resource limits configured to prevent excessive memory usage

### 2. WordPress Integration

- `memcached-object-cache.php`: WordPress drop-in plugin for object caching
- `wordpress-memcached-config.yaml`: ConfigMap with WordPress configuration

### 3. Scripts

- `deploy-memcached.sh`: Deployment script for the complete setup
- `test-memcached.sh`: Test script to verify the integration is working

## Deployment

To deploy the secure Memcached setup, run:

```bash
./deploy-memcached.sh
```

This script will:
1. Deploy Memcached with NetworkPolicy
2. Configure WordPress to use Memcached
3. Install the object cache drop-in plugin

## Testing

To test the Memcached integration with WordPress, run:

```bash
./test-memcached.sh
```

This script performs the following tests:
1. Checks if the Memcached PHP extension is loaded
2. Tests connectivity between WordPress and Memcached
3. Verifies that WordPress object caching is working
4. Confirms that pods outside the WordPress namespace cannot access Memcached

## Security Features

The key security features of this implementation are:

1. **Network Policies**: Only WordPress pods can access Memcached
2. **Internal Service**: Memcached is only exposed within the cluster
3. **No Public Endpoint**: No ingress or external access is configured
4. **Resource Limits**: Prevents resource exhaustion attacks

## Benefits

Using Memcached with WordPress provides:

1. **Improved Performance**: Reduced database queries and faster page loads
2. **Reduced Server Load**: Less strain on the database server
3. **Scalability**: Better handling of traffic spikes
4. **Enhanced Security**: Restricted access model prevents unauthorized use

## Troubleshooting

If you encounter issues with the Memcached integration:

1. Check if the NetworkPolicy is applied: `kubectl get networkpolicy -n wordpress`
2. Verify Memcached is running: `kubectl get pods -n wordpress -l app=memcached`
3. Check WordPress pod logs: `kubectl logs -n wordpress $(kubectl get pods -n wordpress -l app=wordpress -o name | head -1)`
4. Ensure the PHP Memcached extension is installed: Use `test-memcached.sh` 