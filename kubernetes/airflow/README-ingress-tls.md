# Airflow Ingress and TLS Configuration

This directory contains the configuration for Airflow's external access through Traefik ingress with TLS encryption and security hardening.

## Overview

This implementation provides:
- **TLS Encryption**: Automatic Let's Encrypt certificates via cert-manager
- **Security Headers**: Comprehensive security headers for protection
- **Rate Limiting**: DDoS protection with configurable limits
- **HTTP to HTTPS Redirect**: Automatic redirect for secure connections

## Requirements Addressed

- **4.2**: TLS encryption for all communications
- **4.6**: Encrypted network traffic and security headers
- **7.1**: Integration with existing Ingress controllers
- **7.2**: Integration with existing cert-manager for TLS

## Files

### Core Configuration Files

- `airflow-cluster-issuer.yaml` - Let's Encrypt production ClusterIssuer
- `airflow-certificate.yaml` - Explicit TLS certificate resource
- `airflow-ingress-tls.yaml` - Main ingress configuration with security middlewares

### Deployment Scripts

- `deploy-airflow-ingress.sh` - Automated deployment script
- `test-airflow-ingress.sh` - Validation and testing script

## Configuration Details

### Domain Configuration

The ingress is configured for:
- **Domain**: `airflow.gray-beard.com`
- **Protocol**: HTTPS (with HTTP redirect)
- **Port**: 443 (HTTPS), 80 (HTTP redirect)

### Security Features

#### TLS Configuration
- **Certificate Authority**: Let's Encrypt (Production)
- **Key Algorithm**: RSA 2048-bit
- **Renewal**: Automatic (30 days before expiry)
- **HSTS**: Enabled with 1-year max-age

#### Security Headers
- `X-Frame-Options: DENY` - Prevents clickjacking
- `X-Content-Type-Options: nosniff` - Prevents MIME sniffing
- `X-XSS-Protection: 1; mode=block` - XSS protection
- `Content-Security-Policy` - Restricts resource loading
- `Strict-Transport-Security` - Forces HTTPS
- `Referrer-Policy` - Controls referrer information

#### Rate Limiting
- **Rate**: 100 requests per minute per IP
- **Burst**: 200 requests allowed in bursts
- **Scope**: Per source IP address

### Middleware Configuration

#### Security Headers Middleware
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: airflow
spec:
  headers:
    customResponseHeaders:
      X-Frame-Options: "DENY"
      # ... additional headers
```

#### Rate Limiting Middleware
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: airflow
spec:
  rateLimit:
    average: 100
    period: 1m
    burst: 200
```

## Deployment

### Prerequisites

1. **Traefik Ingress Controller** - Must be running in the cluster
2. **cert-manager** - Must be installed and configured
3. **DNS Configuration** - `airflow.gray-beard.com` must point to cluster external IP
4. **Airflow Service** - Airflow webserver service must be running

### Automated Deployment

```bash
# Deploy all ingress and TLS components
./deploy-airflow-ingress.sh
```

### Manual Deployment

```bash
# 1. Create ClusterIssuer
kubectl apply -f airflow-cluster-issuer.yaml

# 2. Create Certificate
kubectl apply -f airflow-certificate.yaml

# 3. Create Ingress with middlewares
kubectl apply -f airflow-ingress-tls.yaml
```

## Validation

### Automated Testing

```bash
# Run comprehensive validation tests
./test-airflow-ingress.sh
```

### Manual Validation

#### Check Certificate Status
```bash
kubectl get certificate airflow-tls-certificate -n airflow
kubectl describe certificate airflow-tls-certificate -n airflow
```

#### Check Ingress Status
```bash
kubectl get ingress airflow-tls -n airflow
kubectl describe ingress airflow-tls -n airflow
```

#### Check TLS Secret
```bash
kubectl get secret airflow-tls-secret -n airflow
kubectl describe secret airflow-tls-secret -n airflow
```

#### Test HTTPS Connectivity
```bash
# Test certificate validity
curl -I https://airflow.gray-beard.com

# Test security headers
curl -I https://airflow.gray-beard.com | grep -E "(X-Frame-Options|X-Content-Type-Options|Strict-Transport-Security)"

# Test HTTP redirect
curl -I http://airflow.gray-beard.com
```

## Troubleshooting

### Common Issues

#### Certificate Not Ready
```bash
# Check certificate status
kubectl describe certificate airflow-tls-certificate -n airflow

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate request
kubectl get certificaterequest -n airflow
```

#### DNS Resolution Issues
```bash
# Test DNS resolution
nslookup airflow.gray-beard.com

# Check external IP
kubectl get svc -n kube-system traefik
```

#### Rate Limiting Issues
```bash
# Check middleware status
kubectl describe middleware rate-limit -n airflow

# Adjust rate limits if needed
kubectl patch middleware rate-limit -n airflow --type='merge' -p='{"spec":{"rateLimit":{"average":200}}}'
```

#### Security Headers Not Applied
```bash
# Check middleware configuration
kubectl describe middleware security-headers -n airflow

# Verify middleware is referenced in ingress
kubectl get ingress airflow-tls -n airflow -o yaml | grep middleware
```

### Certificate Renewal

Certificates are automatically renewed by cert-manager. To force renewal:

```bash
# Delete certificate to trigger renewal
kubectl delete certificate airflow-tls-certificate -n airflow

# Reapply certificate configuration
kubectl apply -f airflow-certificate.yaml
```

## Security Considerations

### Network Security
- All traffic is encrypted with TLS 1.2+
- HTTP traffic is automatically redirected to HTTPS
- Rate limiting prevents basic DDoS attacks

### Application Security
- Security headers prevent common web vulnerabilities
- Content Security Policy restricts resource loading
- Frame options prevent clickjacking attacks

### Certificate Security
- Production Let's Encrypt certificates
- Automatic renewal prevents expiry
- RSA 2048-bit keys provide strong encryption

## Monitoring

### Certificate Monitoring
- Monitor certificate expiry dates
- Set up alerts for certificate renewal failures
- Track certificate issuance metrics

### Traffic Monitoring
- Monitor rate limiting effectiveness
- Track HTTPS vs HTTP traffic ratios
- Monitor security header compliance

### Performance Monitoring
- Monitor TLS handshake performance
- Track ingress response times
- Monitor certificate validation times

## Integration with Existing Infrastructure

### Traefik Integration
- Uses existing Traefik ingress controller
- Leverages existing ACME configuration
- Integrates with existing middleware chain

### cert-manager Integration
- Uses existing cert-manager installation
- Leverages existing ClusterIssuer if available
- Integrates with existing certificate monitoring

### DNS Integration
- Requires DNS record for `airflow.gray-beard.com`
- Integrates with existing domain management
- Supports wildcard certificates if needed

## Next Steps

After successful deployment:

1. **Configure Authentication** (Task 15)
2. **Set up Monitoring** (Tasks 10-12)
3. **Implement Network Policies** (Task 9)
4. **Configure Backup Systems** (Tasks 13-14)

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [OWASP Security Headers](https://owasp.org/www-project-secure-headers/)