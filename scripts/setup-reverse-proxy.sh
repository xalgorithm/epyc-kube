#!/bin/bash

# Setup script for nginx reverse proxy on Proxmox host
# Run this script on your Proxmox host (not in the Kubernetes cluster)

set -e

echo "Setting up nginx reverse proxy for Kubernetes services..."

# Update package list
apt update

# Install nginx if not already installed
if ! command -v nginx &> /dev/null; then
    echo "Installing nginx..."
    apt install -y nginx
else
    echo "Nginx is already installed"
fi

# Create nginx directories if they don't exist
mkdir -p /etc/nginx/snippets
mkdir -p /etc/ssl/certs
mkdir -p /etc/ssl/private

# Copy configuration files
echo "Copying nginx configuration files..."
cp ../config/nginx/nginx-reverse-proxy.conf /etc/nginx/sites-available/k8s-reverse-proxy
cp ../config/nginx/ssl-params.conf /etc/nginx/snippets/
cp ../config/nginx/security-headers.conf /etc/nginx/snippets/

# Create a self-signed certificate for testing (replace with real certificates later)
if [ ! -f /etc/ssl/certs/wildcard.crt ]; then
    echo "Creating self-signed SSL certificate for testing..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/wildcard.key \
        -out /etc/ssl/certs/wildcard.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=*.gray-beard.com" \
        -addext "subjectAltName=DNS:*.gray-beard.com,DNS:kampfzwerg.gray-beard.com,DNS:*.kampfzwerg.gray-beard.com"
    
    chmod 600 /etc/ssl/private/wildcard.key
    chmod 644 /etc/ssl/certs/wildcard.crt
fi

# Enable the site
if [ ! -L /etc/nginx/sites-enabled/k8s-reverse-proxy ]; then
    ln -s /etc/nginx/sites-available/k8s-reverse-proxy /etc/nginx/sites-enabled/
    echo "Enabled k8s-reverse-proxy site"
fi

# Disable default nginx site if it exists
if [ -L /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
    echo "Disabled default nginx site"
fi

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

# Restart nginx
echo "Restarting nginx..."
systemctl restart nginx
systemctl enable nginx

# Check nginx status
systemctl status nginx --no-pager

echo ""
echo "✅ Nginx reverse proxy setup complete!"
echo ""
echo "Your services are now accessible at:"
echo "  - https://grafana.gray-beard.com"
echo "  - https://airflow.gray-beard.com"
echo "  - https://automate.gray-beard.com"
echo "  - https://automate2.gray-beard.com"
echo "  - https://ethos.gray-beard.com"
echo "  - https://kampfzwerg.gray-beard.com"
echo "  - https://login.gray-beard.com"
echo "  - https://notify.gray-beard.com"
echo "  - https://blackrock.gray-beard.com"
echo "  - https://vault.gray-beard.com"
echo ""
echo "⚠️  Note: Currently using self-signed certificates."
echo "   Replace /etc/ssl/certs/wildcard.crt and /etc/ssl/private/wildcard.key"
echo "   with your real SSL certificates for production use."
echo ""
echo "🔧 To get Let's Encrypt certificates, run:"
echo "   certbot --nginx -d grafana.gray-beard.com -d airflow.gray-beard.com [add all your domains]"