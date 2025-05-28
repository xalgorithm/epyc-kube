#!/bin/bash
# WireGuard setup script for colocation server
# This script sets up a secure WireGuard connection to the home network

set -e

# Configuration variables - EDIT THESE
OPNSENSE_PUBLIC_IP="" # Your home OPNsense public IP
OPNSENSE_WIREGUARD_PORT="51820"
OPNSENSE_WIREGUARD_PUBLIC_KEY="" # Public key from OPNsense WireGuard setup
HOME_NETWORK="192.168.100.0/24"
COLO_NETWORK="10.0.1.208/29"
VPN_SUBNET="10.10.10.0/24"
VPN_COLO_IP="10.10.10.2"
VPN_OPNSENSE_IP="10.10.10.1"

# Make sure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

echo "========================================================"
echo "Setting up WireGuard on colocation server"
echo "========================================================"
echo "Home network: $HOME_NETWORK"
echo "Colocation network: $COLO_NETWORK"
echo "VPN subnet: $VPN_SUBNET"
echo ""

# Check if configuration is set
if [ -z "$OPNSENSE_PUBLIC_IP" ] || [ -z "$OPNSENSE_WIREGUARD_PUBLIC_KEY" ]; then
    echo "ERROR: Please edit this script and set the configuration variables first."
    exit 1
fi

# Install WireGuard
echo "Installing WireGuard..."
apt update
apt install -y wireguard wireguard-tools iptables-persistent

# Generate keys if they don't exist
if [ ! -f /etc/wireguard/private.key ]; then
    echo "Generating WireGuard keys..."
    mkdir -p /etc/wireguard
    wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
    chmod 600 /etc/wireguard/private.key
fi

# Display public key for OPNsense configuration
echo ""
echo "========================================================"
echo "YOUR WIREGUARD PUBLIC KEY (add this to OPNsense):"
cat /etc/wireguard/public.key
echo "========================================================"
echo ""

# Create WireGuard configuration
echo "Creating WireGuard configuration..."
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = ${VPN_COLO_IP}/24
ListenPort = ${OPNSENSE_WIREGUARD_PORT}

# Enable routing for the VPN
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = ${OPNSENSE_WIREGUARD_PUBLIC_KEY}
AllowedIPs = ${HOME_NETWORK}, ${VPN_OPNSENSE_IP}/32
Endpoint = ${OPNSENSE_PUBLIC_IP}:${OPNSENSE_WIREGUARD_PORT}
PersistentKeepalive = 25
EOF

# Configure firewall
echo "Configuring firewall rules..."
cat > /etc/wireguard/firewall-rules.sh << EOF
#!/bin/bash

# Clear existing rules
iptables -F INPUT
iptables -F FORWARD

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (change port if needed)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow WireGuard
iptables -A INPUT -p udp --dport ${OPNSENSE_WIREGUARD_PORT} -j ACCEPT

# Allow specific services from home network via WireGuard
iptables -A INPUT -i wg0 -s ${HOME_NETWORK} -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i wg0 -s ${HOME_NETWORK} -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -i wg0 -s ${HOME_NETWORK} -p tcp --dport 6443 -j ACCEPT  # Kubernetes API

# Allow forwarding between interfaces
iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Save rules
iptables-save > /etc/iptables/rules.v4
EOF

chmod +x /etc/wireguard/firewall-rules.sh

# Enable IP forwarding permanently
echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

# Apply firewall rules
echo "Applying firewall rules..."
/etc/wireguard/firewall-rules.sh

# Enable and start WireGuard
echo "Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

# Add cron job to check WireGuard connectivity
echo "Setting up monitoring..."
(crontab -l 2>/dev/null || echo "") | grep -v "wg-monitor.sh" | crontab -
cat > /etc/wireguard/wg-monitor.sh << EOF
#!/bin/bash
if ! ping -c 1 -W 5 ${VPN_OPNSENSE_IP} > /dev/null 2>&1; then
    echo "WireGuard connection down, restarting..."
    systemctl restart wg-quick@wg0
    # Send alert if you have a notification system
    # notify-admin "WireGuard tunnel down, restarted automatically"
fi
EOF
chmod +x /etc/wireguard/wg-monitor.sh
(crontab -l ; echo "*/5 * * * * /etc/wireguard/wg-monitor.sh") | crontab -

echo ""
echo "========================================================"
echo "WireGuard setup complete!"
echo "========================================================"
echo "WireGuard interface: wg0"
echo "WireGuard IP: ${VPN_COLO_IP}"
echo "WireGuard port: ${OPNSENSE_WIREGUARD_PORT}"
echo ""
echo "To check WireGuard status:"
echo "  wg show"
echo ""
echo "To check firewall rules:"
echo "  iptables -L -v -n"
echo ""
echo "To test connectivity (after OPNsense is configured):"
echo "  ping ${VPN_OPNSENSE_IP}"
echo "  ping 192.168.100.1"
echo "========================================================" 