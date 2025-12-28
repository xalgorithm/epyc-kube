# Nginx Reverse Proxy Setup for Kubernetes Services

> 📚 **Navigation:** [Main README](../README.md) | [Documentation Index](README.md) | [Scripts Reference](../scripts/README.md) | [Config Files](../config/README.md)

This setup creates an nginx reverse proxy that forwards traffic from standard ports (80/443) to your Kubernetes NodePorts, making all your services accessible on their proper domains.

**Related Documentation:**
- [Traefik Connectivity](traefik-external-connectivity-fix.md) - Troubleshooting LoadBalancer connectivity
- [Configuration Files](../config/nginx/) - Nginx configuration templates
- [Setup Script](../scripts/setup-reverse-proxy.sh) - Automated deployment
- [Test Script](../scripts/test-all-domains.sh) - Connectivity verification

## 🚀 Quick Setup

### Step 1: Install the Reverse Proxy

Run this on your **Proxmox host** (not in Kubernetes):

```bash
# Copy the files to your Proxmox host first
scp nginx-reverse-proxy.conf ssl-params.conf security-headers.conf setup-reverse-proxy.sh root@10.0.1.211:/root/

# SSH to your Proxmox host
ssh root@10.0.1.211

# Run the setup script
cd /root
./setup-reverse-proxy.sh
```

### Step 2: Update DNS Records

Update your DNS records to point all domains to your Proxmox host IP:

```
grafana.gray-beard.com      → 10.0.1.211
airflow.gray-beard.com      → 10.0.1.211
automate.gray-beard.com     → 10.0.1.211
automate2.gray-beard.com    → 10.0.1.211
ethos.gray-beard.com        → 10.0.1.211
ethosenv.gray-beard.com     → 10.0.1.211
kampfzwerg.gray-beard.com        → 10.0.1.211
login.gray-beard.com        → 10.0.1.211
notify.gray-beard.com       → 10.0.1.211
blackrock.gray-beard.com    → 10.0.1.211
couchdb.blackrock.gray-beard.com → 10.0.1.211
vault.gray-beard.com        → 10.0.1.211
```

### Step 3: Get Let's Encrypt Certificates (Optional but Recommended)

After DNS propagation (wait 5-10 minutes), run:

```bash
./setup-letsencrypt.sh
```

## 🔧 How It Works

### Architecture
```
Internet → nginx (Proxmox Host:80/443) → Kubernetes NodePort (30080/30443) → Traefik → Services
```

### Traffic Flow
1. **HTTP (port 80)**: Redirects to HTTPS, except for ACME challenges
2. **HTTPS (port 443)**: Proxies to Kubernetes NodePort 30443
3. **Traefik**: Routes traffic based on Host headers to appropriate services

### Load Balancing
The nginx configuration includes all three Kubernetes nodes with failover:
- Primary: `10.0.1.211:30443`
- Backup: `10.0.1.212:30443`
- Backup: `10.0.1.213:30443`

## 📊 Monitoring and Maintenance

### Check Service Health
```bash
./check-services.sh
```

### View nginx Logs
```bash
# Access logs
tail -f /var/log/nginx/access.log

# Error logs
tail -f /var/log/nginx/error.log
```

### Reload nginx Configuration
```bash
nginx -t && systemctl reload nginx
```

## 🔒 Security Features

- **HSTS**: Forces HTTPS for all future requests
- **Security Headers**: XSS protection, content type sniffing protection
- **Modern TLS**: Only TLS 1.2 and 1.3 with secure ciphers
- **WebSocket Support**: For applications that need real-time communication

## 🛠️ Troubleshooting

### Service Not Accessible
1. Check if nginx is running: `systemctl status nginx`
2. Check if Kubernetes NodePorts are accessible: `curl -k https://10.0.1.211:30443`
3. Check nginx configuration: `nginx -t`
4. Check DNS resolution: `nslookup grafana.gray-beard.com`

### SSL Certificate Issues
1. Check certificate validity: `openssl x509 -in /etc/ssl/certs/wildcard.crt -text -noout`
2. Renew Let's Encrypt certificates: `certbot renew`
3. Test certificate renewal: `certbot renew --dry-run`

### High Availability
If you want true high availability, you can:
1. Install the same nginx configuration on multiple Proxmox hosts
2. Use a load balancer (like HAProxy) in front of multiple nginx instances
3. Use DNS round-robin or a service like Cloudflare for failover

## 📝 Configuration Files

- **Main Config**: `/etc/nginx/sites-available/k8s-reverse-proxy`
- **SSL Settings**: `/etc/nginx/snippets/ssl-params.conf`
- **Security Headers**: `/etc/nginx/snippets/security-headers.conf`
- **SSL Certificates**: `/etc/ssl/certs/wildcard.crt` and `/etc/ssl/private/wildcard.key`

## 🔄 Automatic Updates

The setup includes:
- **Automatic SSL renewal**: Certificates renew automatically via cron
- **Service monitoring**: Use the provided health check script
- **Log rotation**: nginx logs are automatically rotated by logrotate

## ✅ Success Verification

After setup, you should be able to access:
- ✅ https://grafana.gray-beard.com (Grafana dashboard)
- ✅ https://kampfzwerg.gray-beard.com (WordPress site)
- ✅ https://automate.gray-beard.com (N8N automation)
- ✅ All other configured domains

All traffic will be properly SSL-encrypted and load-balanced across your Kubernetes nodes!