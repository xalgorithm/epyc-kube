#!/bin/bash

# Manual Proxmox Firewall Commands for MetalLB
# Run these commands directly on your Proxmox host

echo "🔧 Manual Proxmox Firewall Configuration for MetalLB"
echo "===================================================="
echo ""
echo "📋 Run these commands on your Proxmox host:"
echo ""

cat << 'EOF'
# 1. Check current firewall rules
echo "Current FORWARD rules:"
iptables -L FORWARD -n --line-numbers | head -10

# 2. Check existing MetalLB rules
echo "Existing MetalLB rules:"
iptables -L FORWARD -n | grep '198\.55\.108' || echo "No MetalLB rules found"

# 3. Add firewall rules for MetalLB subnet
echo "Adding MetalLB firewall rules..."
iptables -I FORWARD 1 -d 10.0.2.8/29 -p tcp --dport 80 -j ACCEPT
iptables -I FORWARD 1 -d 10.0.2.8/29 -p tcp --dport 443 -j ACCEPT
iptables -I FORWARD 1 -d 10.0.2.8/29 -j ACCEPT
iptables -I FORWARD 1 -s 10.0.2.8/29 -j ACCEPT

# 4. Verify rules were added
echo "New firewall rules:"
iptables -L FORWARD -n | grep '198\.55\.108'

# 5. Save rules permanently
echo "Saving firewall rules..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# 6. Test connectivity
echo "Testing connectivity..."
ping -c 3 10.0.2.9
curl -I --connect-timeout 10 http://10.0.2.9 || echo "HTTP test failed - may need additional configuration"

echo "✅ Firewall configuration complete!"
EOF

echo ""
echo "📋 Alternative: Copy and paste individual commands:"
echo ""
echo "# Add HTTP rule:"
echo "iptables -I FORWARD 1 -d 10.0.2.8/29 -p tcp --dport 80 -j ACCEPT"
echo ""
echo "# Add HTTPS rule:"
echo "iptables -I FORWARD 1 -d 10.0.2.8/29 -p tcp --dport 443 -j ACCEPT"
echo ""
echo "# Add general MetalLB rule:"
echo "iptables -I FORWARD 1 -d 10.0.2.8/29 -j ACCEPT"
echo ""
echo "# Add return traffic rule:"
echo "iptables -I FORWARD 1 -s 10.0.2.8/29 -j ACCEPT"
echo ""
echo "# Save rules:"
echo "iptables-save > /etc/iptables/rules.v4"
echo ""
echo "# Test:"
echo "curl -I http://10.0.2.9"
