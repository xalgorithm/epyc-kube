# Traefik External Connectivity Fix

> 📚 **Navigation:** [Main README](../README.md) | [Documentation Index](README.md) | [Proxmox MetalLB Config](proxmox-metallb-subnet-configuration.md)

## Problem Summary

External HTTP/HTTPS connectivity to Traefik (via MetalLB LoadBalancer IP 10.0.2.9) is timing out, even though:
- ✅ Traefik is running correctly
- ✅ MetalLB is announcing the IP successfully  
- ✅ Internal connectivity (from within the cluster) works
- ✅ External ICMP/ping works
- ❌ External HTTP/HTTPS times out

**Related Documentation:**
- [Proxmox Network Configuration](proxmox-metallb-subnet-configuration.md) - MetalLB subnet setup
- [Fix Script](../scripts/fix-external-traefik-connectivity.sh) - Automated firewall rule application
- [MetalLB Configurations](../kubernetes/metallb-configurations/) - Kubernetes resources
- [Reverse Proxy Setup](REVERSE-PROXY-SETUP.md) - Nginx proxy configuration

## Root Cause

The issue is with **firewall rules at the network gateway level** blocking HTTP/HTTPS traffic to the MetalLB subnet (10.0.2.8/29). ICMP packets are allowed through, but TCP traffic on ports 80 and 443 is being blocked by the FORWARD chain.

## Diagnosis Results

### From Inside Cluster (✅ Working)
```bash
$ kubectl run curl-test --image=curlimages/curl --rm -it -- curl -I http://10.0.2.9
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8
...
```

### From K8s Nodes (✅ Working)
```bash
$ ssh aragorn curl -I http://10.0.2.9
HTTP/1.1 404 Not Found
...
```

### From External (❌ Blocked)
```bash
$ curl -I --connect-timeout 5 http://10.0.2.9
curl: (28) Failed to connect to 10.0.2.9 port 80 after 5002 ms: Timeout
```

### But Ping Works (✅ Working)
```bash
$ ping -c 3 10.0.2.9
64 bytes from 10.0.2.9: icmp_seq=0 ttl=52 time=28.030 ms
...
```

## Solution

Add iptables FORWARD rules on the gateway/firewall to allow HTTP/HTTPS traffic to the MetalLB subnet.

### Required Firewall Rules

```bash
# Allow HTTP (port 80)
iptables -I FORWARD 1 -d 10.0.2.8/29 -p tcp --dport 80 -j ACCEPT

# Allow HTTPS (port 443)
iptables -I FORWARD 1 -d 10.0.2.8/29 -p tcp --dport 443 -j ACCEPT

# Allow general traffic to MetalLB subnet
iptables -I FORWARD 1 -d 10.0.2.8/29 -j ACCEPT

# Allow return traffic from MetalLB subnet
iptables -I FORWARD 1 -s 10.0.2.8/29 -j ACCEPT
```

### Automated Fix Script

Use the provided script to apply the rules automatically:

```bash
# Option 1: Run on the gateway/firewall host directly
sudo ./scripts/fix-external-traefik-connectivity.sh

# Option 2: Run remotely via SSH
scp scripts/fix-external-traefik-connectivity.sh root@gateway-ip:/tmp/
ssh root@gateway-ip "bash /tmp/fix-external-traefik-connectivity.sh"
```

### Manual Application

If you can't access the gateway/firewall host, you may need to:

1. **Contact your hosting provider** to add firewall rules for:
   - Source: Any (0.0.0.0/0)
   - Destination: 10.0.2.8/29
   - Ports: 80, 443
   - Protocol: TCP
   - Action: ALLOW

2. **Check datacenter firewall settings** in your hosting control panel

3. **Verify upstream router configuration**

## Network Architecture

```
Internet
    ↓
Gateway/Firewall (10.0.1.209) ← FIREWALL RULES NEEDED HERE
    ↓
K8s Nodes (10.0.1.211-213)
    ↓
MetalLB L2 Advertisement (10.0.2.9)
    ↓
Traefik LoadBalancer Service
    ↓
Traefik Pod (10.42.x.x)
```

## Verification

After applying the firewall rules, test from an external network:

```bash
# Test HTTP
curl -I http://10.0.2.9
# Expected: HTTP/1.1 404 Not Found (or any HTTP response)

# Test HTTPS
curl -I -k https://10.0.2.9
# Expected: HTTP response

# Test a specific domain (once DNS is configured)
curl -I http://your-domain.com
```

## Persistence

The fix script automatically saves rules to persist across reboots using:
- `/etc/iptables/rules.v4` (Debian/Ubuntu)
- `netfilter-persistent` (if available)
- `/etc/network/if-pre-up.d/iptables` (fallback)

## Troubleshooting

### Rules Applied But Still Not Working

1. **Check if rules are in correct order:**
   ```bash
   iptables -L FORWARD -n --line-numbers
   ```
   The ACCEPT rules should be BEFORE any DROP rules.

2. **Check NAT rules:**
   ```bash
   iptables -t nat -L -n -v
   ```

3. **Check routing:**
   ```bash
   ip route get 10.0.2.9
   ```

4. **Check from K8s nodes:**
   ```bash
   ssh aragorn "curl -I http://10.0.2.9"
   ```
   If this works but external doesn't, the issue is definitely the firewall.

5. **Check MetalLB logs:**
   ```bash
   kubectl logs -n metallb-system -l component=speaker --tail=50
   ```
   Look for "serviceAnnounced" messages.

### Alternative: Use NodePort Instead

If firewall rules can't be modified, you can temporarily use NodePort:

```bash
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"NodePort"}}'
```

Then access via: `http://10.0.1.211:<nodeport>`

## Related Files

- `/Users/xalg/dev/terraform/epyc/scripts/fix-external-traefik-connectivity.sh` - Automated fix script
- `/Users/xalg/dev/terraform/epyc/scripts/configure-proxmox-firewall-for-metallb.sh` - Alternative Proxmox-specific script
- `/Users/xalg/dev/terraform/epyc/kubernetes/metallb-configurations/` - MetalLB configuration files

## Current MetalLB Configuration

**IP Pool:**
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: dedicated-subnet-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.2.9-10.0.2.14
  autoAssign: true
```

**L2 Advertisement:**
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: dedicated-subnet-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - dedicated-subnet-pool
```

## Status

- **Date**: October 26, 2025
- **Status**: Firewall rules need to be applied on gateway (10.0.1.209)
- **Traefik**: ✅ Working
- **MetalLB**: ✅ Working and announcing IP
- **Internal Connectivity**: ✅ Working
- **External Connectivity**: ❌ Blocked by firewall


