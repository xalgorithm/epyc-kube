#!/bin/bash

# Script to deploy Memcached with secure access from WordPress only
# This script configures a Memcached instance with network policies
# that only allow access from the WordPress pods

set -e

echo "Deploying Memcached with secure access configuration..."

# Create the wordpress namespace if it doesn't exist
if ! kubectl get namespace wordpress >/dev/null 2>&1; then
  echo "Creating WordPress namespace..."
  kubectl create namespace wordpress
fi

# Apply the Memcached deployment with NetworkPolicy
echo "Deploying Memcached with restricted access..."
kubectl apply -f memcached-deployment.yaml

# Apply the WordPress Memcached configuration
echo "Configuring WordPress for Memcached integration..."
kubectl apply -f wordpress-memcached-config.yaml

# Check if WordPress deployment exists
if kubectl get deployment wordpress -n wordpress >/dev/null 2>&1; then
  echo "Patching WordPress deployment to use Memcached..."
  
  # Add the config volume to WordPress deployment
  kubectl patch deployment wordpress -n wordpress --type=json -p='[
    {
      "op": "add", 
      "path": "/spec/template/spec/volumes/-", 
      "value": {
        "name": "memcached-config",
        "configMap": {
          "name": "wordpress-memcached-config"
        }
      }
    }
  ]'
  
  # Add the volume mount to WordPress containers
  kubectl patch deployment wordpress -n wordpress --type=json -p='[
    {
      "op": "add", 
      "path": "/spec/template/spec/containers/0/volumeMounts/-", 
      "value": {
        "name": "memcached-config",
        "mountPath": "/var/www/html/wp-content/memcached-config.php",
        "subPath": "wp-config-memcached.php"
      }
    }
  ]'
  
  # Restart WordPress deployment to apply changes
  kubectl rollout restart deployment wordpress -n wordpress
  
  # Wait for rollout completion
  kubectl rollout status deployment wordpress -n wordpress
fi

# Copy the Memcached Object Cache plugin to WordPress
echo "Installing Memcached Object Cache for WordPress..."

# Create a temporary pod to copy the file to WordPress persistent storage
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wp-file-installer
  namespace: wordpress
spec:
  containers:
  - name: installer
    image: alpine:3.16
    command: ["/bin/sh", "-c", "apk add --no-cache curl && sleep 3600"]
    volumeMounts:
    - name: wp-content
      mountPath: /wp-content
    - name: cache-plugin
      mountPath: /cache-plugin
  volumes:
  - name: wp-content
    persistentVolumeClaim:
      claimName: wordpress-pvc
  - name: cache-plugin
    configMap:
      name: memcached-object-cache
EOF

# Wait for the installer pod to be ready
echo "Waiting for installer pod to be ready..."
kubectl wait --for=condition=Ready pod/wp-file-installer -n wordpress --timeout=60s

# Create ConfigMap with the object cache file
kubectl create configmap memcached-object-cache -n wordpress --from-file=object-cache.php=memcached-object-cache.php

# Copy the file to the WordPress wp-content folder
kubectl exec -n wordpress wp-file-installer -- /bin/sh -c "mkdir -p /wp-content/wp-content && cp /cache-plugin/object-cache.php /wp-content/wp-content/"

# Clean up the installer pod
kubectl delete pod wp-file-installer -n wordpress

echo "Memcached deployment complete."
echo "Memcached is now accessible only to WordPress pods."
echo ""
echo "To verify the connection, check WordPress performance and run:"
echo "kubectl exec -n wordpress \$(kubectl get pods -n wordpress -l app=wordpress -o name | head -1) -- php -r 'var_dump(wp_cache_get(\"test\"));'" 