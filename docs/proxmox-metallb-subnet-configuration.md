# Proxmox Network Configuration for MetalLB Subnet

## Overview

The `10.0.2.8/29` subnet needs to be properly configured in Proxmox to ensure MetalLB can announce and route traffic to the LoadBalancer IPs.

## Current Configuration Analysis

Based on your Terraform configuration:
- **Public Bridge**: `vmbr1` 
- **Private Bridge**: `vmbr2`
- **Node IPs**: `10.0.1.211-213` (on public bridge)
- **MetalLB Subnet**: `10.0.2.8/29` (needs routing)

## Required Proxmox Configuration

### 1. Network Bridge Configuration

The `10.0.2.8/29` subnet needs to be routable through your public bridge (`vmbr1`). You have several options:

#### Option A: Add Subnet to Existing Bridge (Recommended)
```bash
# On Proxmox host, add the subnet as an additional IP range
# This allows the bridge to route traffic to the subnet

# Check current bridge configuration
ip addr show vmbr1

# Add subnet route (if not automatically routed)
ip route add 10.0.2.8/29 dev vmbr1

# Make permanent by adding to /etc/network/interfaces
```

#### Option B: Create Dedicated Bridge for MetalLB
```bash
# Create a new bridge specifically for MetalLB traffic
# This provides better isolation but requires more configuration
```

### 2. Proxmox Network Interfaces Configuration

Edit `/etc/network/interfaces` on your Proxmox host:

```bash
# Current configuration (example)
auto vmbr1
iface vmbr1 inet static
    address 10.0.1.XXX/24
    gateway 10.0.1.1
    bridge-ports eth0
    bridge-stp off
    bridge-fd 0

# Add MetalLB subnet routing
# Option 1: Add as additional address
auto vmbr1:1
iface vmbr1:1 inet static
    address 10.0.2.8/29

# Option 2: Add routing rules
up ip route add 10.0.2.8/29 dev vmbr1
down ip route del 10.0.2.8/29 dev vmbr1
```

### 3. Firewall Configuration

Ensure Proxmox firewall allows traffic to the MetalLB subnet:

```bash
# Add firewall rules for MetalLB subnet
# Allow HTTP/HTTPS traffic to MetalLB IPs
iptables -A FORWARD -d 10.0.2.8/29 -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -d 10.0.2.8/29 -p tcp --dport 443 -j ACCEPT

# Allow all traffic to MetalLB subnet (less restrictive)
iptables -A FORWARD -d 10.0.2.8/29 -j ACCEPT
```

## Implementation Steps

### Step 1: Check Current Network Configuration

```bash
# SSH to your Proxmox host
ssh root@your-proxmox-host

# Check current bridge configuration
ip addr show vmbr1
ip route show

# Check if subnet is already routable
ping -c 1 10.0.2.9
```

### Step 2: Configure Network Routing

Choose one of these approaches:

#### Approach A: Simple Routing (Recommended)
```bash
# Add route for MetalLB subnet through public bridge
ip route add 10.0.2.8/29 dev vmbr1

# Test connectivity
ping -c 1 10.0.2.9

# If successful, make permanent
echo "up ip route add 10.0.2.8/29 dev vmbr1" >> /etc/network/interfaces
echo "down ip route del 10.0.2.8/29 dev vmbr1" >> /etc/network/interfaces
```

#### Approach B: Bridge Alias (Alternative)
```bash
# Add subnet as bridge alias
ip addr add 10.0.2.8/29 dev vmbr1

# Make permanent in /etc/network/interfaces
cat >> /etc/network/interfaces << EOF

auto vmbr1:metallb
iface vmbr1:metallb inet static
    address 10.0.2.8/29
EOF
```

### Step 3: Configure Firewall Rules

```bash
# Allow traffic to MetalLB subnet
iptables -I FORWARD -d 10.0.2.8/29 -j ACCEPT

# Save iptables rules (method varies by distribution)
iptables-save > /etc/iptables/rules.v4
# or
netfilter-persistent save
```

### Step 4: Verify Configuration

```bash
# Check routing
ip route show | grep 198.55.108

# Test connectivity from Proxmox host
curl -I http://10.0.2.9

# Check from external network
# (from another machine)
curl -I http://10.0.2.9
```

## Terraform Integration

Your `terraform.tfvars` already includes the subnet:
```hcl
metallb_addresses = ["10.0.1.214/32", "10.0.2.8/29"]
```

However, this doesn't automatically configure Proxmox networking. The subnet configuration must be done on the Proxmox host itself.

## Troubleshooting

### Issue: MetalLB IPs not reachable externally

**Symptoms:**
- MetalLB assigns IPs correctly
- Services show EXTERNAL-IP from subnet
- External connectivity fails

**Solutions:**
1. **Check Proxmox routing:**
   ```bash
   ip route show | grep 198.55.108
   ```

2. **Verify bridge configuration:**
   ```bash
   brctl show vmbr1
   ip addr show vmbr1
   ```

3. **Test from Proxmox host:**
   ```bash
   curl -I http://10.0.2.9
   ```

4. **Check firewall rules:**
   ```bash
   iptables -L FORWARD | grep 198.55.108
   ```

### Issue: ARP resolution problems

**Symptoms:**
- Intermittent connectivity
- ARP table issues

**Solutions:**
1. **Enable proxy ARP:**
   ```bash
   echo 1 > /proc/sys/net/ipv4/conf/vmbr1/proxy_arp
   ```

2. **Add permanent proxy ARP:**
   ```bash
   echo "net.ipv4.conf.vmbr1.proxy_arp = 1" >> /etc/sysctl.conf
   ```

## Next Steps

1. **Immediate**: Configure Proxmox network routing for `10.0.2.8/29`
2. **Test**: Verify external connectivity to `10.0.2.9`
3. **DNS**: Update DNS records to point to new IPs
4. **Monitor**: Check MetalLB speaker logs for announcement issues

## Network Topology

```
Internet
    ↓
Router/Firewall (10.0.1.1)
    ↓
Proxmox Host (10.0.1.XXX)
    ↓
vmbr1 Bridge
    ├── Node IPs: 10.0.1.211-213
    └── MetalLB Subnet: 10.0.2.8/29
            ├── 10.0.2.9 (Traefik)
            ├── 10.0.2.10 (Available)
            ├── 10.0.2.11 (Available)
            ├── 10.0.2.12 (Available)
            ├── 10.0.2.13 (Available)
            └── 10.0.2.14 (Available)
```

## Security Considerations

1. **Firewall Rules**: Only allow necessary ports (80, 443) to MetalLB subnet
2. **Network Segmentation**: Consider isolating MetalLB traffic if needed
3. **Monitoring**: Monitor traffic to MetalLB IPs for anomalies
4. **Access Control**: Ensure only authorized services can request LoadBalancer IPs
