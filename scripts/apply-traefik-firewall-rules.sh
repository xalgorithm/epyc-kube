#!/bin/bash

# Quick one-liner to apply Traefik firewall rules
# This script should be run on the gateway/firewall host (10.0.1.209)

METALLB_SUBNET="10.0.2.8/29"

echo "Adding firewall rules for MetalLB subnet..."

# Add the required rules
iptables -I FORWARD 1 -d $METALLB_SUBNET -p tcp --dport 80 -j ACCEPT && \
iptables -I FORWARD 1 -d $METALLB_SUBNET -p tcp --dport 443 -j ACCEPT && \
iptables -I FORWARD 1 -d $METALLB_SUBNET -j ACCEPT && \
iptables -I FORWARD 1 -s $METALLB_SUBNET -j ACCEPT && \
echo "✓ Rules added successfully"

# Save the rules
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 && echo "✓ Rules saved"

# Show the rules
echo ""
echo "Current FORWARD rules for MetalLB:"
iptables -L FORWARD -n --line-numbers | grep "198\.55\.108"

echo ""
echo "Testing connectivity..."
timeout 5 curl -I http://10.0.2.9 2>&1 | head -3 || echo "HTTP test completed"


