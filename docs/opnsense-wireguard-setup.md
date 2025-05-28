# OPNsense WireGuard Configuration Guide

This guide provides step-by-step instructions for configuring WireGuard on OPNsense to establish a secure connection with your colocation server.

## Prerequisites

- OPNsense 22.1 or later
- WireGuard plugin installed
- Public IP address for your OPNsense router
- Colocation server public key (from running the `setup-colo-wireguard.sh` script)

## Installation Steps

### 1. Install WireGuard Plugin

1. Navigate to **System → Firmware → Plugins**
2. Search for "wireguard"
3. Click the **+** button to install the plugin
4. Wait for installation to complete

### 2. Configure WireGuard Local Server

1. Navigate to **VPN → WireGuard → Local**
2. Click **+ Add** to create a new local configuration
3. Fill in the fields:
   - **Name**: `ColoLink`
   - **Listen Port**: `51820` (or another available port)
   - **DNS**: Leave empty (we'll use existing DNS)
   - **Tunnel Address**: `10.10.10.1/24` (dedicated VPN subnet)
   - **Private Key**: Click **Generate** to create a new key
   - **Public Key**: Will be automatically generated
   - **Disable Routes**: Unchecked
   - **Gateway**: Leave empty
   - **Disable from config**: Unchecked
4. Click **Save**

### 3. Configure WireGuard Peer (Colocation Server)

1. Navigate to **VPN → WireGuard → Endpoints**
2. Click **+ Add** to create a new endpoint configuration
3. Fill in the fields:
   - **Name**: `ColoServer`
   - **Public Key**: (Paste the public key from the colocation server)
   - **Shared Secret**: Leave empty (WireGuard doesn't use shared secrets)
   - **Allowed IPs**: `10.0.1.208/29, 10.10.10.2/32`
   - **Endpoint Address**: (Colocation server's public IP address)
   - **Endpoint Port**: `51820`
   - **Keep Alive**: `25` (seconds)
   - **Turn on dynamic endpoint addresses**: Unchecked (colo server has static IP)
4. Click **Save**

### 4. Assign WireGuard Interface

1. Navigate to **Interfaces → Assignments**
2. From the dropdown menu, select the WireGuard interface (`wg0`)
3. Click **+ Add**
4. Click the newly created interface (likely named `OPT1` or similar)
5. Configure the interface:
   - **Enable**: Checked
   - **Description**: `COLO_VPN`
   - **IPv4 Configuration Type**: `None` (IP is assigned by WireGuard config)
   - **IPv6 Configuration Type**: `None`
6. Click **Save**
7. Click **Apply Changes**

### 5. Configure Firewall Rules

1. Navigate to **Firewall → Rules → COLO_VPN**
2. Click **+ Add** to create a new rule
3. Configure the first rule (allow established connections):
   - **Action**: Pass
   - **Interface**: COLO_VPN
   - **Direction**: in
   - **TCP/IP Version**: IPv4
   - **Protocol**: Any
   - **Source**: Any
   - **Destination**: Any
   - **Advanced Features → Gateway**: Default
   - **Advanced Features → TCP Flags**: Check `established`
4. Click **Save**

5. Click **+ Add** to create another rule
6. Configure the second rule (allow specific service access):
   - **Action**: Pass
   - **Interface**: COLO_VPN
   - **Direction**: in
   - **TCP/IP Version**: IPv4
   - **Protocol**: TCP
   - **Source**: LAN net (or specific hosts that need access)
   - **Destination**: Network: `10.0.1.208/29`
   - **Destination port range**: (Select the ports for services you need, e.g., 443, 6443 for Kubernetes API)
7. Click **Save**

8. Click **+ Add** to create a final blocking rule
9. Configure the third rule (block all other traffic):
   - **Action**: Block
   - **Interface**: COLO_VPN
   - **Direction**: in
   - **TCP/IP Version**: IPv4
   - **Protocol**: Any
   - **Source**: Any
   - **Destination**: Any
   - **Advanced Features → Log**: Checked (for troubleshooting)
10. Click **Save**
11. Click **Apply Changes**

### 6. Enable WireGuard Service

1. Navigate to **VPN → WireGuard → General**
2. Check **Enable WireGuard**
3. Click **Save**
4. Click **Apply**

### 7. Add Static Routes (if needed)

If you need to route traffic from other local subnets through the VPN:

1. Navigate to **System → Routes → Configuration**
2. Click **+ Add** to create a new route
3. Configure the route:
   - **Network Address**: `10.0.1.208`
   - **Subnet Mask**: `29`
   - **Gateway**: Select the WireGuard interface gateway
4. Click **Save**
5. Click **Apply Changes**

## Testing the Connection

1. Navigate to **Diagnostics → Ping**
2. Enter the WireGuard IP of the colocation server (`10.10.10.2`)
3. Click **Ping**
4. If successful, try pinging a service on the colocation network (`10.0.1.208`)

## Troubleshooting

### Check WireGuard Status

1. Navigate to **VPN → WireGuard → Status**
2. Verify that the connection shows as established
3. Check the transfer statistics to confirm data is flowing

### Check Firewall Logs

1. Navigate to **Firewall → Log Files → Live View**
2. Look for any blocked connections related to WireGuard

### Command Line Diagnostics

Connect to OPNsense via SSH and run:

```bash
# Check WireGuard service status
service wireguard status

# View current connections
wg show

# Check logs
grep -i wireguard /var/log/system.log
```

## Security Considerations

1. **Expose Only Necessary Services**: Only create firewall rules for services that need to be accessed from the home network
2. **Use Strong Keys**: Always generate new keys rather than reusing existing ones
3. **Regular Updates**: Keep OPNsense updated to get the latest security patches
4. **Monitor Logs**: Regularly check the firewall logs for suspicious activity

## Maintenance

### Key Rotation

Rotate WireGuard keys quarterly:

1. Generate new keys on both OPNsense and the colocation server
2. Update peer configurations on both sides
3. Restart WireGuard services

### Regular Testing

Periodically test the VPN connection by:

1. Pinging devices across the VPN
2. Accessing services on the colocation server
3. Verifying firewall rules are working as expected

## Backup Configuration

Always back up your OPNsense configuration after making changes:

1. Navigate to **System → Configuration → Backups**
2. Click **Download**
3. Save the backup file in a secure location 