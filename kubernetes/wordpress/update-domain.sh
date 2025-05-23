#!/bin/bash
set -e

# Apply the updated configurations with a more reliable approach
echo "Updating Kubernetes configurations..."

# Get the latest versions of resources and update them
echo "Updating ingress configuration..."
kubectl apply -f ingress.yaml || kubectl replace --force -f ingress.yaml

# The deployments need special handling due to potential conflicts
echo "Updating WordPress deployment configurations..."

# Apply just the domain changes without modifying other parts of the deployments
# For deployment.yaml
kubectl patch deployment wordpress -n wordpress --type=json -p '[
  {
    "op": "replace", 
    "path": "/spec/template/spec/containers/0/env/4/value", 
    "value": "define('\''WP_HOME'\'', '\''https://kampfzwerg.gray-beard.com'\'');\ndefine('\''WP_SITEURL'\'', '\''https://kampfzwerg.gray-beard.com'\'');\n"
  }
]'

# For wordpress-deployment.yaml (update only if it exists and differs from deployment.yaml)
if kubectl get deployment wordpress-deployment -n wordpress 2>/dev/null; then
  kubectl patch deployment wordpress-deployment -n wordpress --type=json -p '[
    {
      "op": "replace", 
      "path": "/spec/template/spec/containers/0/env/4/value", 
      "value": "define('\''WP_HOME'\'', '\''https://kampfzwerg.gray-beard.com'\'');\ndefine('\''WP_SITEURL'\'', '\''https://kampfzwerg.gray-beard.com'\'');\n"
    }
  ]' || echo "Warning: Could not update wordpress-deployment.yaml, but continuing..."
fi

# Get the WordPress pod name
WORDPRESS_POD=$(kubectl get pods -n wordpress -l app=wordpress -o jsonpath="{.items[0].metadata.name}")

echo "WordPress pod: $WORDPRESS_POD"

# Update URLs in the WordPress database
echo "Updating WordPress database URLs..."
kubectl exec -n wordpress $WORDPRESS_POD -- wp search-replace 'https://metaphysicalninja.com' 'https://kampfzwerg.gray-beard.com' --all-tables || echo "Warning: Failed to update HTTPS URLs in database"

# Also update without https to catch any http URLs
kubectl exec -n wordpress $WORDPRESS_POD -- wp search-replace 'http://metaphysicalninja.com' 'https://kampfzwerg.gray-beard.com' --all-tables || echo "Warning: Failed to update HTTP URLs in database"

echo "Domain update complete. The WordPress site should now be accessible at https://kampfzwerg.gray-beard.com"
echo "Note: You may need to clear your browser cache or wait for DNS propagation."

# Restart WordPress pod to ensure changes take effect
echo "Restarting WordPress pod..."
kubectl rollout restart deployment/wordpress -n wordpress

echo "Waiting for WordPress pod to be ready..."
kubectl rollout status deployment/wordpress -n wordpress

echo "Domain change completed successfully!" 