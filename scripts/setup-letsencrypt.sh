#!/bin/bash

# Setup Let's Encrypt certificates for all domains
# Run this script AFTER setting up the reverse proxy and ensuring DNS points to this server

set -e

echo "Setting up Let's Encrypt certificates..."

# Install certbot if not already installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt update
    apt install -y certbot python3-certbot-nginx
else
    echo "Certbot is already installed"
fi

# List of all your domains
DOMAINS=(
    "grafana.admin.im"
    "airflow.admin.im"
    "automate.admin.im"
    "automate2.admin.im"
    "ethos.admin.im"
    "ethosenv.admin.im"
    "kampfzwerg.gray-beard.com"
    "login.admin.im"
    "notify.admin.im"
    "blackrock.admin.im"
    "couchdb.blackrock.admin.im"
    "vault.admin.im"
)

# Build certbot command with all domains
CERTBOT_CMD="certbot --nginx --agree-tos --no-eff-email --email admin@example.com"

for domain in "${DOMAINS[@]}"; do
    CERTBOT_CMD="$CERTBOT_CMD -d $domain"
done

echo "Running certbot for all domains..."
echo "Command: $CERTBOT_CMD"

# Run certbot
eval $CERTBOT_CMD

# Setup automatic renewal
echo "Setting up automatic certificate renewal..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

echo ""
echo "✅ Let's Encrypt certificates setup complete!"
echo "🔄 Automatic renewal is configured to run daily at 12:00 PM"
echo ""
echo "To test renewal, run: certbot renew --dry-run"