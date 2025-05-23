#!/bin/bash

# Get WordPress ingress IP
echo "Getting WordPress ingress IP..."
WP_INGRESS_IP=$(kubectl get ingress -n wordpress wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Verify the domain is pointing to the correct IP
echo "Verifying DNS configuration for kampfzwerg.me..."
DOMAIN_IP=$(dig +short kampfzwerg.me)

echo "WordPress ingress IP: $WP_INGRESS_IP"
echo "kampfzwerg.me resolves to: $DOMAIN_IP"

if [ "$WP_INGRESS_IP" = "$DOMAIN_IP" ]; then
  echo "✅ DNS configuration is correct! kampfzwerg.me points to the WordPress ingress IP."
else
  echo "⚠️  Warning: DNS configuration may be incorrect."
  echo "The WordPress ingress IP is $WP_INGRESS_IP, but kampfzwerg.me resolves to $DOMAIN_IP."
  echo "Please update your DNS records to point kampfzwerg.me to $WP_INGRESS_IP."
  echo "Note: DNS changes may take time to propagate."
fi

# Check if the site is reachable
echo
echo "Checking if the WordPress site is reachable at https://kampfzwerg.me..."
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://kampfzwerg.me > /dev/null 2>&1; then
  echo "✅ The site is reachable at https://kampfzwerg.me!"
else
  echo "⚠️  Warning: Could not connect to https://kampfzwerg.me."
  echo "This could be due to DNS propagation delay, SSL certificate issues, or the site not being ready."
  echo "Please try again later, or check the WordPress pod logs for issues."
fi 