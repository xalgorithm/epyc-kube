#!/bin/bash
# Tailscale backup connection setup script for colocation server
# This script sets up Tailscale as a secondary VPN connection for redundancy

set -e

# Configuration variables - EDIT THESE
COLO_NETWORK="10.0.1.208/29"
TAILSCALE_ACL_TAG="colo-server" # Optional: for use with Tailscale ACLs

# Make sure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

echo "========================================================"
echo "Setting up Tailscale as backup connection"
echo "========================================================"
echo "Colocation network: $COLO_NETWORK"
echo ""

# Check if Tailscale is already installed
if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale is already installed. Checking version..."
    CURRENT_VERSION=$(tailscale version | head -n 1 | awk '{print $2}')
    echo "Current version: $CURRENT_VERSION"
else
    # Install Tailscale
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Configure Tailscale
echo "Configuring Tailscale with minimal access and advertising routes..."

# Check if Tailscale is already authenticated
if tailscale status | grep -q "tailscale login"; then
    echo "Tailscale is not authenticated. Starting authentication..."
    
    # Configure with minimal access and route advertisement
    tailscale up \
        --advertise-routes=${COLO_NETWORK} \
        --accept-dns=false \
        --shields-up \
        --reset
    
    echo "Please complete authentication by visiting the URL above."
    echo "Waiting for authentication to complete..."
    
    # Wait for authentication (timeout after 5 minutes)
    timeout=300
    while ! tailscale status | grep -q "Connected" && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout-1))
    done
    
    if [ $timeout -eq 0 ]; then
        echo "Timed out waiting for Tailscale authentication."
        echo "Please run 'tailscale up' manually and complete the authentication."
        exit 1
    fi
else
    echo "Tailscale is already authenticated. Reconfiguring..."
    
    # Reconfigure with route advertisement
    tailscale up \
        --advertise-routes=${COLO_NETWORK} \
        --accept-dns=false \
        --shields-up \
        --reset
fi

# Create a monitoring script for Tailscale
echo "Setting up Tailscale monitoring..."
cat > /usr/local/bin/tailscale-monitor.sh << 'EOF'
#!/bin/bash

# Check if Tailscale is connected
if ! tailscale status | grep -q "Connected"; then
    echo "Tailscale connection down, restarting..."
    tailscale up --advertise-routes=$COLO_NETWORK --accept-dns=false --shields-up
    # Send alert if you have a notification system
    # notify-admin "Tailscale connection down, restarted automatically"
fi

# Check if primary WireGuard connection is down
# Only enable Tailscale exit node if WireGuard is down
if ! ping -c 1 -W 5 10.10.10.1 > /dev/null 2>&1; then
    # WireGuard is down, enable Tailscale as exit node
    echo "WireGuard down, enabling Tailscale as exit node..."
    tailscale up --advertise-exit-node --advertise-routes=$COLO_NETWORK --accept-dns=false
else
    # WireGuard is up, disable Tailscale as exit node
    echo "WireGuard up, disabling Tailscale as exit node..."
    tailscale up --advertise-routes=$COLO_NETWORK --accept-dns=false --shields-up
fi
EOF

# Replace placeholder with actual network
sed -i "s|\$COLO_NETWORK|${COLO_NETWORK}|g" /usr/local/bin/tailscale-monitor.sh

chmod +x /usr/local/bin/tailscale-monitor.sh

# Add cron job to check Tailscale connectivity
(crontab -l 2>/dev/null || echo "") | grep -v "tailscale-monitor.sh" | crontab -
(crontab -l ; echo "*/10 * * * * /usr/local/bin/tailscale-monitor.sh") | crontab -

# Add service to start Tailscale at boot
echo "Enabling Tailscale service at boot..."
systemctl enable tailscaled

echo ""
echo "========================================================"
echo "Tailscale backup connection setup complete!"
echo "========================================================"
echo "Tailscale status:"
tailscale status
echo ""
echo "IMPORTANT: You need to authorize the subnet routes in the Tailscale admin console:"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Find this machine"
echo "3. Approve the advertised routes: $COLO_NETWORK"
echo ""
echo "To test Tailscale connectivity:"
echo "  From home device with Tailscale installed:"
echo "  ping $(tailscale ip)"
echo "========================================================" 