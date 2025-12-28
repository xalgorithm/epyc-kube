# Secure Network Bridge: Colocation to Home Network

> 📚 **Navigation:** [Main README](../README.md) | [Documentation Index](README.md) | [Network Checklist](network-bridge-checklist.md) | [OPNsense Setup](opnsense-wireguard-setup.md)

## Overview

This document outlines the implementation of a secure network bridge between:
- Colocation server network: `10.0.1.208/29`
- Home network: `192.168.100.0/24` 

The solution uses WireGuard (implemented in OPNsense) as the primary VPN technology with a fallback to Tailscale for redundancy.

**Related Documentation:**
- [Network Bridge Deployment Checklist](network-bridge-checklist.md) - Step-by-step deployment guide
- [OPNsense WireGuard Setup](opnsense-wireguard-setup.md) - Detailed OPNsense configuration
- [Setup Script](../scripts/setup-colo-wireguard.sh) - Automated colocation setup
- [Proxmox Network Configuration](proxmox-metallb-subnet-configuration.md) - MetalLB subnet setup

## Network Diagram

```
+----------------------+          +---------------------+
| Colocation Server    |          | Home Network        |
| 10.0.1.208/29    |          | 192.168.100.0/24      |
|                      |          |                     |
|  +--------------+    |  WireGuard  +--------------+   |
|  | Kubernetes   |<---|------------>| OPNsense     |   |
|  | Services     |    |          |  | Router       |   |
|  +--------------+    |          |  +--------------+   |
|         ^            |          |         |           |
+---------|------------+          +---------|----------- +
          |                                 |
          |           Tailscale             |
          +-------------------------------->+
                    (Backup Path)
```

## Security Measures

1. **Encrypted Tunnels**: All traffic between networks is encrypted using WireGuard's modern cryptographic methods.
2. **Restricted Access**: Only specified services/IPs allowed through the tunnel.
3. **Redundant Connectivity**: Tailscale provides a backup connection method.
4. **Regular Key Rotation**: WireGuard keys are rotated regularly.
5. **Firewall Rules**: Strict firewall rules on both sides of the connection.

## Implementation Steps

### 1. WireGuard Setup on OPNsense

#### OPNsense Configuration

1. Navigate to VPN → WireGuard in the OPNsense interface
2. Create a new Local Configuration:
   - Name: `ColoLink`
   - Listen Port: `51820` (or another available port)
   - DNS: Leave empty (using existing DNS)
   - Tunnel Address: `10.10.10.1/24` (dedicated VPN subnet)
   - Generate a new Private Key
   - Save and copy the Public Key

3. Create WireGuard Peer:
   - Name: `ColoServer`
   - Public Key: (Public key from the colocation server)
   - Allowed IPs: `10.0.1.208/29, 10.10.10.2/32`
   - Endpoint: (Colocation server's public IP address)
   - Endpoint Port: `51820`
   - Keep Alive: `25` (seconds)
   - Save configuration

4. Enable the WireGuard service

#### Firewall Rules on OPNsense

Add the following rules to the WireGuard interface:

1. Allow established connections: 
   - Action: Pass
   - Protocol: Any
   - Source: Any
   - Destination: Any
   - Advanced: Check "Established" option

2. Allow access to specific services (example for Kubernetes API):
   - Action: Pass
   - Protocol: TCP
   - Source: 192.168.100.0/24
   - Destination: 10.0.1.208/29
   - Destination Port: 6443

3. Block all other traffic:
   - Action: Block
   - Protocol: Any
   - Source: Any
   - Destination: Any
   - Log: Enabled (for troubleshooting)

### 2. WireGuard Setup on Colocation Server

1. Install WireGuard:
   ```bash
   apt update && apt install -y wireguard
   ```

2. Generate keys:
   ```bash
   wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
   chmod 600 /etc/wireguard/private.key
   ```

3. Create configuration file (`/etc/wireguard/wg0.conf`):
   ```ini
   [Interface]
   PrivateKey = <content of private.key>
   Address = 10.10.10.2/24
   ListenPort = 51820

   [Peer]
   PublicKey = <OPNsense WireGuard public key>
   AllowedIPs = 192.168.100.0/24, 10.10.10.1/32
   Endpoint = <OPNsense public IP>:51820
   PersistentKeepalive = 25
   ```

4. Enable and start WireGuard:
   ```bash
   systemctl enable wg-quick@wg0
   systemctl start wg-quick@wg0
   ```

5. Configure firewall on colocation server:
   ```bash
   # Allow WireGuard traffic
   iptables -A INPUT -p udp --dport 51820 -j ACCEPT
   
   # Allow established connections
   iptables -A INPUT -i wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT
   
   # Allow specific services from home network
   iptables -A INPUT -i wg0 -s 192.168.100.0/24 -p tcp --dport 80 -j ACCEPT
   iptables -A INPUT -i wg0 -s 192.168.100.0/24 -p tcp --dport 443 -j ACCEPT
   
   # Block other incoming traffic on WireGuard interface
   iptables -A INPUT -i wg0 -j DROP
   
   # Save rules
   iptables-save > /etc/iptables/rules.v4
   ```

### 3. Tailscale Backup Configuration

#### On Colocation Server

1. Install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```

2. Set up with minimum access:
   ```bash
   tailscale up --advertise-routes=10.0.1.208/29 --accept-dns=false --shields-up
   ```

#### On Home Network

1. Install Tailscale on OPNsense via the plugin system or on a designated device
2. Connect to the same Tailscale account
3. Approve route advertisement in the Tailscale admin console

### 4. Kubernetes Configuration

Update your Kubernetes configurations to be aware of the new network routes:

1. Add route to the home network in your Kubernetes nodes:
   ```bash
   ip route add 192.168.100.0/24 via 10.10.10.1 dev wg0
   ```

2. Make this route persistent by adding to `/etc/network/interfaces` or equivalent.

### 5. Testing the Connection

1. Basic connectivity:
   ```bash
   # From OPNsense/home network
   ping 10.10.10.2
   ping 10.0.1.208
   
   # From colocation server
   ping 10.10.10.1
   ping 192.168.100.1
   ```

2. Service access:
   ```bash
   # Test Kubernetes API access
   curl -k https://10.0.1.208:6443
   ```

## Maintenance Practices

### Regular Security Updates

1. Update OPNsense regularly
2. Update WireGuard and Tailscale on all systems
3. Review firewall logs weekly for unexpected connection attempts

### Key Rotation

1. Rotate WireGuard keys quarterly:
   - Generate new keys on both sides
   - Update peer configurations
   - Restart WireGuard services

### Monitoring

1. Set up monitoring for the VPN tunnel status:
   ```bash
   # Check WireGuard status
   wg show
   
   # Set up regular ping tests between networks
   */5 * * * * ping -c 1 10.10.10.1 || notify-admin "WireGuard tunnel down"
   ```

2. Configure alerts for tunnel failures

## Troubleshooting

### WireGuard Connection Issues

1. Check if WireGuard is running:
   ```bash
   systemctl status wg-quick@wg0
   ```

2. Verify firewall isn't blocking:
   ```bash
   iptables -L -v -n | grep 51820
   ```

3. Test with temporary disabled firewall (not in production)

### Routing Problems

1. Check routing tables:
   ```bash
   ip route
   ```

2. Verify packets are flowing through WireGuard:
   ```bash
   tcpdump -i wg0
   ```

### Failover Testing

Periodically test the Tailscale backup by temporarily stopping WireGuard:
```bash
systemctl stop wg-quick@wg0
# Verify services remain accessible through Tailscale
# Then restore WireGuard
systemctl start wg-quick@wg0
```

## Security Considerations

1. **Exposed Services**: Only expose necessary services across the VPN
2. **Network Segmentation**: Keep critical systems segregated
3. **Monitoring**: Actively monitor for unauthorized access attempts
4. **Regular Audits**: Conduct security audits of the VPN configuration

## Appendix

### OPNsense WireGuard Plugin CLI Commands

For advanced troubleshooting, access the OPNsense shell and use:

```bash
# Check WireGuard service status
service wireguard status

# View current connections
wg show

# Check logs
grep -i wireguard /var/log/system.log
``` 