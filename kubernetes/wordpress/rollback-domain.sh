#!/bin/bash
set -e

echo "Rolling back domain change from kampfzwerg.gray-beard.com to metaphysicalninja.com..."

# Update ingress back to the original domain
echo "Updating ingress configuration..."
# Update ingress.yaml first
sed -i '' 's/kampfzwerg.gray-beard.com/metaphysicalninja.com/g' ingress.yaml
kubectl apply -f ingress.yaml || kubectl replace --force -f ingress.yaml

# Update deployment configurations
echo "Updating WordPress deployment configurations..."

# Patch the deployment to revert the domain
kubectl patch deployment wordpress -n wordpress --type=json -p '[
  {
    "op": "replace", 
    "path": "/spec/template/spec/containers/0/env/4/value", 
    "value": "define('\''WP_HOME'\'', '\''https://metaphysicalninja.com'\'');\ndefine('\''WP_SITEURL'\'', '\''https://metaphysicalninja.com'\'');\n"
  }
]'

# Update wordpress-deployment.yaml back to original
sed -i '' 's/kampfzwerg.gray-beard.com/metaphysicalninja.com/g' wordpress-deployment.yaml

# For wordpress-deployment.yaml (update only if it exists)
if kubectl get deployment wordpress-deployment -n wordpress 2>/dev/null; then
  kubectl patch deployment wordpress-deployment -n wordpress --type=json -p '[
    {
      "op": "replace", 
      "path": "/spec/template/spec/containers/0/env/4/value", 
      "value": "define('\''WP_HOME'\'', '\''https://metaphysicalninja.com'\'');\ndefine('\''WP_SITEURL'\'', '\''https://metaphysicalninja.com'\'');\n"
    }
  ]' || echo "Warning: Could not update wordpress-deployment.yaml, but continuing..."
fi

# Get the WordPress pod name
WORDPRESS_POD=$(kubectl get pods -n wordpress -l app=wordpress -o jsonpath="{.items[0].metadata.name}")

echo "WordPress pod: $WORDPRESS_POD"

# Update URLs in the WordPress database
echo "Updating WordPress database URLs back to original..."
kubectl exec -n wordpress $WORDPRESS_POD -- wp search-replace 'https://kampfzwerg.gray-beard.com' 'https://metaphysicalninja.com' --all-tables || echo "Warning: Failed to update HTTPS URLs in database"

# Also update without https to catch any http URLs
kubectl exec -n wordpress $WORDPRESS_POD -- wp search-replace 'http://kampfzwerg.gray-beard.com' 'https://metaphysicalninja.com' --all-tables || echo "Warning: Failed to update HTTP URLs in database"

echo "Rollback complete. The WordPress site should now be accessible at https://metaphysicalninja.com"
echo "Note: You may need to clear your browser cache or wait for DNS propagation."

# Restart WordPress pod to ensure changes take effect
echo "Restarting WordPress pod..."
kubectl rollout restart deployment/wordpress -n wordpress

echo "Waiting for WordPress pod to be ready..."
kubectl rollout status deployment/wordpress -n wordpress

echo "Domain rollback completed successfully!" 