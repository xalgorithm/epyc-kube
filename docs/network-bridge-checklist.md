# Network Bridge Deployment Checklist

Use this checklist to ensure proper implementation of the secure network bridge between your colocation server and home network.

## Pre-Deployment Preparation

- [ ] Document current network configurations
  - [ ] Colocation server network: 10.0.1.208/29
  - [ ] Home network: 192.168.100.0/24
  - [ ] Document all services that need to be accessible from each network

- [ ] Verify firewall configurations
  - [ ] Document current open ports on colocation server
  - [ ] Document current open ports on OPNsense router
  - [ ] Note any existing VPN configurations

- [ ] Create a backup
  - [ ] Backup OPNsense configuration
  - [ ] Backup colocation server network configuration
  - [ ] Backup Kubernetes configurations

## Deployment Steps

### Phase 1: WireGuard Primary Connection

- [ ] On Colocation Server:
  - [ ] Run `scripts/setup-colo-wireguard.sh`
  - [ ] Note the generated public key: ________________
  - [ ] Verify WireGuard service is running: `systemctl status wg-quick@wg0`

- [ ] On OPNsense:
  - [ ] Install WireGuard plugin
  - [ ] Configure local WireGuard server following `docs/opnsense-wireguard-setup.md`
  - [ ] Add colocation server as peer using the noted public key
  - [ ] Create necessary firewall rules
  - [ ] Enable WireGuard service
  - [ ] Note the OPNsense WireGuard public key: ________________

- [ ] Update Colocation Server with OPNsense Public Key:
  - [ ] Edit `/etc/wireguard/wg0.conf` and update peer public key
  - [ ] Restart WireGuard: `systemctl restart wg-quick@wg0`

### Phase 2: Testing Primary Connection

- [ ] From Colocation Server:
  - [ ] Ping WireGuard interface on OPNsense: `ping 10.10.10.1`
  - [ ] Ping OPNsense LAN IP: `ping 192.168.100.1`
  - [ ] Verify route to home network: `ip route | grep 192.168.100.0`

- [ ] From Home Network:
  - [ ] Ping WireGuard interface on colocation server: `ping 10.10.10.2`
  - [ ] Ping a service on colocation network: `ping 10.0.1.208`
  - [ ] Test service access (e.g., Kubernetes API): `curl -k https://10.0.1.208:6443`

### Phase 3: Tailscale Backup Connection

- [ ] Create Tailscale account if needed
- [ ] On Colocation Server:
  - [ ] Run `scripts/setup-tailscale-backup.sh`
  - [ ] Complete Tailscale authentication
  - [ ] Note Tailscale IP: ________________

- [ ] On Home Network:
  - [ ] Install Tailscale on OPNsense or designated device
  - [ ] Connect to the same Tailscale account
  - [ ] Approve route advertisements in Tailscale admin console

- [ ] Test Tailscale connectivity:
  - [ ] Ping Tailscale IP of colocation server
  - [ ] Ping a service on colocation network through Tailscale

### Phase 4: Failover Testing

- [ ] Test WireGuard to Tailscale failover:
  - [ ] Stop WireGuard on colocation server: `systemctl stop wg-quick@wg0`
  - [ ] Verify Tailscale takes over (may take up to 10 minutes for cron job)
  - [ ] Verify services remain accessible
  - [ ] Restart WireGuard: `systemctl start wg-quick@wg0`

- [ ] Test Tailscale to WireGuard failover:
  - [ ] Stop Tailscale: `systemctl stop tailscaled`
  - [ ] Verify services remain accessible via WireGuard
  - [ ] Restart Tailscale: `systemctl start tailscaled`

## Post-Deployment Tasks

- [ ] Update Kubernetes configurations if needed
  - [ ] Update any hardcoded IPs in service configurations
  - [ ] Verify cluster accessibility

- [ ] Document final network configuration
  - [ ] Create network diagram
  - [ ] Document all open ports and services
  - [ ] Document failover procedures

- [ ] Set up monitoring
  - [ ] Configure alerts for VPN connection failures
  - [ ] Set up regular connectivity tests
  - [ ] Configure logging for security events

- [ ] Schedule maintenance tasks
  - [ ] Quarterly key rotation for WireGuard
  - [ ] Regular testing of failover capability
  - [ ] Regular review of firewall logs

## Security Verification

- [ ] Verify only necessary services are exposed
  - [ ] Run port scans from each network
  - [ ] Verify firewall rules are blocking unauthorized access

- [ ] Test from unauthorized networks
  - [ ] Attempt to access services from a different network
  - [ ] Verify attempts are blocked

- [ ] Verify encryption
  - [ ] Check WireGuard handshake is successful
  - [ ] Verify data is properly encrypted (e.g., with packet capture)

## Rollback Plan

In case of deployment issues, follow these steps to rollback:

1. Restore OPNsense configuration from backup
2. On colocation server:
   ```bash
   systemctl stop wg-quick@wg0
   systemctl disable wg-quick@wg0
   systemctl stop tailscaled
   systemctl disable tailscaled
   ```
3. Restore original network configurations
4. Verify services are accessible through original means 