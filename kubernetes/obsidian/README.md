# Obsidian Stack SSL Certificate Management

> 📚 **Navigation:** [Main README](../../README.md) | [Documentation Index](../../docs/README.md) | [Cert-Manager Module](../../modules/cert-manager/)

This document provides comprehensive guidance for managing SSL certificates in the Obsidian stack using cert-manager and Let's Encrypt.

**Related Documentation:**
- [Main README](../../README.md) - Platform overview
- [Cert-Manager Module](../../modules/cert-manager/) - Certificate automation
- [Reverse Proxy Setup](../../docs/REVERSE-PROXY-SETUP.md) - Nginx proxy configuration

## Overview

The Obsidian stack consists of two main services that require SSL certificates:
- **Obsidian Application**: Accessible at `blackrock.gray-beard.com`
- **CouchDB Database**: Accessible at `couchdb.blackrock.gray-beard.com`

SSL certificates are automatically managed using cert-manager with Let's Encrypt as the certificate authority. The system supports both staging and production certificate environments.

## Architecture

### Certificate Management Components

- **cert-manager**: Kubernetes controller for automatic certificate provisioning and renewal
- **ClusterIssuer**: Defines the certificate authority (Let's Encrypt) configuration
- **Certificate Resources**: Automatically created by cert-manager based on ingress annotations
- **TLS Secrets**: Kubernetes secrets containing the issued certificates and private keys
- **Traefik Ingress Controller**: Serves HTTPS traffic using the certificates

### Certificate Flow

1. Ingress resources are applied with cert-manager annotations
2. cert-manager detects the annotations and creates Certificate resources
3. ACME challenge is initiated with Let's Encrypt
4. Upon successful validation, certificates are issued and stored as Kubernetes secrets
5. Traefik ingress controller uses the certificates to serve HTTPS traffic
6. cert-manager automatically renews certificates before expiration

## SSL Certificate Configuration

### Production Configuration

For production certificates, use the following ingress resources:
- `obsidian-ingress-tls.yaml` - Obsidian application with production certificates
- `couchdb-ingress-tls.yaml` - CouchDB with production certificates

**Key Configuration Elements:**
```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - blackrock.gray-beard.com
    secretName: obsidian-tls
```

### Staging Configuration

For staging/testing certificates, use:
- `obsidian-ingress-tls-staging.yaml` - Obsidian application with staging certificates
- `couchdb-ingress-tls-staging.yaml` - CouchDB with staging certificates

**Key Configuration Elements:**
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
```

### Certificate Secrets

Certificates are stored as Kubernetes TLS secrets:
- `obsidian-tls` - Contains certificate for blackrock.gray-beard.com
- `couchdb-tls` - Contains certificate for couchdb.blackrock.gray-beard.com

## Switching Between Staging and Production Certificates

### Prerequisites

Before switching certificate environments:

1. Verify cert-manager is running:
   ```bash
   kubectl get pods -n cert-manager
   ```

2. Check ClusterIssuer availability:
   ```bash
   kubectl get clusterissuer
   ```

3. Ensure DNS records point to your ingress IP:
   ```bash
   nslookup blackrock.gray-beard.com
   nslookup couchdb.blackrock.gray-beard.com
   ```

### Switching to Staging Certificates

**Use Case**: Testing certificate configuration, avoiding Let's Encrypt rate limits

1. **Delete existing certificates and secrets** (if switching from production):
   ```bash
   kubectl delete certificate obsidian-tls couchdb-tls -n obsidian
   kubectl delete secret obsidian-tls couchdb-tls -n obsidian
   ```

2. **Apply staging ingress resources**:
   ```bash
   kubectl apply -f obsidian-ingress-tls-staging.yaml
   kubectl apply -f couchdb-ingress-tls-staging.yaml
   ```

3. **Verify certificate requests**:
   ```bash
   kubectl get certificates -n obsidian
   kubectl describe certificate obsidian-tls -n obsidian
   kubectl describe certificate couchdb-tls -n obsidian
   ```

4. **Monitor certificate issuance**:
   ```bash
   kubectl get certificaterequests -n obsidian
   kubectl logs -n cert-manager deployment/cert-manager
   ```

### Switching to Production Certificates

**Use Case**: Deploying to production environment

1. **Delete staging certificates and secrets**:
   ```bash
   kubectl delete certificate obsidian-tls couchdb-tls -n obsidian
   kubectl delete secret obsidian-tls couchdb-tls -n obsidian
   ```

2. **Apply production ingress resources**:
   ```bash
   kubectl apply -f obsidian-ingress-tls.yaml
   kubectl apply -f couchdb-ingress-tls.yaml
   ```

3. **Verify certificate requests**:
   ```bash
   kubectl get certificates -n obsidian
   kubectl describe certificate obsidian-tls -n obsidian
   kubectl describe certificate couchdb-tls -n obsidian
   ```

4. **Validate production certificates**:
   ```bash
   ./validate-ssl-certificates.sh
   ```

### Automated Switching Script

Create a script to automate the switching process:

```bash
#!/bin/bash
# switch-certificates.sh

ENVIRONMENT=${1:-staging}

if [ "$ENVIRONMENT" = "production" ]; then
    echo "Switching to production certificates..."
    kubectl delete certificate obsidian-tls couchdb-tls -n obsidian --ignore-not-found
    kubectl delete secret obsidian-tls couchdb-tls -n obsidian --ignore-not-found
    kubectl apply -f obsidian-ingress-tls.yaml
    kubectl apply -f couchdb-ingress-tls.yaml
elif [ "$ENVIRONMENT" = "staging" ]; then
    echo "Switching to staging certificates..."
    kubectl delete certificate obsidian-tls couchdb-tls -n obsidian --ignore-not-found
    kubectl delete secret obsidian-tls couchdb-tls -n obsidian --ignore-not-found
    kubectl apply -f obsidian-ingress-tls-staging.yaml
    kubectl apply -f couchdb-ingress-tls-staging.yaml
else
    echo "Usage: $0 [staging|production]"
    exit 1
fi

echo "Waiting for certificates to be issued..."
kubectl wait --for=condition=Ready certificate/obsidian-tls -n obsidian --timeout=300s
kubectl wait --for=condition=Ready certificate/couchdb-tls -n obsidian --timeout=300s

echo "Certificate switch complete!"
```

## Troubleshooting Guide

### Common Certificate Issues

#### 1. Certificate Request Stuck in Pending State

**Symptoms:**
```bash
kubectl get certificates -n obsidian
NAME           READY   SECRET         AGE
obsidian-tls   False   obsidian-tls   5m
```

**Diagnosis:**
```bash
kubectl describe certificate obsidian-tls -n obsidian
kubectl get certificaterequests -n obsidian
kubectl describe certificaterequest <request-name> -n obsidian
```

**Common Causes & Solutions:**

- **DNS Resolution Issues**: Verify domain resolves to ingress IP
  ```bash
  nslookup blackrock.gray-beard.com
  kubectl get ingress -n obsidian -o wide
  ```

- **ClusterIssuer Not Ready**: Check ClusterIssuer status
  ```bash
  kubectl get clusterissuer
  kubectl describe clusterissuer letsencrypt-prod
  ```

- **ACME Challenge Failure**: Check challenge resources
  ```bash
  kubectl get challenges -n obsidian
  kubectl describe challenge <challenge-name> -n obsidian
  ```

#### 2. Certificate Expired or Invalid

**Symptoms:**
- Browser shows certificate warnings
- SSL validation script reports expired certificates

**Diagnosis:**
```bash
./validate-ssl-certificates.sh
openssl s_client -connect blackrock.gray-beard.com:443 -servername blackrock.gray-beard.com
```

**Solutions:**

- **Force Certificate Renewal**:
  ```bash
  kubectl delete certificate obsidian-tls -n obsidian
  kubectl delete secret obsidian-tls -n obsidian
  # Reapply ingress to trigger new certificate request
  kubectl apply -f obsidian-ingress-tls.yaml
  ```

- **Check cert-manager Logs**:
  ```bash
  kubectl logs -n cert-manager deployment/cert-manager
  ```

#### 3. Certificate Secret Not Found

**Symptoms:**
```bash
kubectl get secret obsidian-tls -n obsidian
Error from server (NotFound): secrets "obsidian-tls" not found
```

**Solutions:**

- **Verify Certificate Resource Exists**:
  ```bash
  kubectl get certificates -n obsidian
  ```

- **Check Certificate Status**:
  ```bash
  kubectl describe certificate obsidian-tls -n obsidian
  ```

- **Recreate Certificate**:
  ```bash
  kubectl delete certificate obsidian-tls -n obsidian
  kubectl apply -f obsidian-ingress-tls.yaml
  ```

#### 4. Rate Limiting from Let's Encrypt

**Symptoms:**
- Certificate requests fail with rate limit errors
- cert-manager logs show "too many certificates already issued"

**Solutions:**

- **Switch to Staging Environment**:
  ```bash
  kubectl apply -f obsidian-ingress-tls-staging.yaml
  kubectl apply -f couchdb-ingress-tls-staging.yaml
  ```

- **Wait for Rate Limit Reset**: Let's Encrypt rate limits reset weekly

- **Use Different Domain**: If testing, use a different subdomain

### Diagnostic Commands

#### Certificate Status
```bash
# Check all certificates
kubectl get certificates -A

# Check specific certificate details
kubectl describe certificate obsidian-tls -n obsidian

# Check certificate events
kubectl get events -n obsidian --field-selector involvedObject.kind=Certificate
```

#### cert-manager Health
```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check webhook connectivity
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations
```

#### ACME Challenges
```bash
# List active challenges
kubectl get challenges -A

# Check challenge details
kubectl describe challenge <challenge-name> -n obsidian

# Check challenge events
kubectl get events -n obsidian --field-selector involvedObject.kind=Challenge
```

#### TLS Secrets
```bash
# List TLS secrets
kubectl get secrets -n obsidian --field-selector type=kubernetes.io/tls

# Examine certificate in secret
kubectl get secret obsidian-tls -n obsidian -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Monitoring and Maintenance Procedures

### Certificate Lifecycle Monitoring

#### 1. Automated Certificate Validation

Use the provided validation script for regular monitoring:

```bash
# Run validation script
./validate-ssl-certificates.sh

# Schedule regular validation (add to crontab)
0 6 * * * /path/to/validate-ssl-certificates.sh
```

#### 2. Certificate Expiration Monitoring

**Monitor certificate expiration dates:**

```bash
# Check certificate expiration
kubectl get certificates -n obsidian -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

# Get detailed expiration info
kubectl get secret obsidian-tls -n obsidian -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -enddate -noout
```

**Set up expiration alerts:**

Create a monitoring script that alerts when certificates expire within 30 days:

```bash
#!/bin/bash
# certificate-expiry-check.sh

NAMESPACE="obsidian"
SECRETS=("obsidian-tls" "couchdb-tls")
WARNING_DAYS=30

for secret in "${SECRETS[@]}"; do
    if kubectl get secret "$secret" -n "$NAMESPACE" >/dev/null 2>&1; then
        expiry_date=$(kubectl get secret "$secret" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -enddate -noout | cut -d= -f2)
        expiry_epoch=$(date -d "$expiry_date" +%s)
        current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [ $days_until_expiry -lt $WARNING_DAYS ]; then
            echo "WARNING: Certificate $secret expires in $days_until_expiry days"
            # Add alerting mechanism here (email, Slack, etc.)
        fi
    fi
done
```

#### 3. cert-manager Health Monitoring

**Monitor cert-manager components:**

```bash
# Check cert-manager deployment health
kubectl get deployments -n cert-manager

# Monitor cert-manager resource usage
kubectl top pods -n cert-manager

# Check for cert-manager errors
kubectl logs -n cert-manager deployment/cert-manager --tail=100 | grep -i error
```

### Maintenance Procedures

#### 1. Regular Certificate Renewal Testing

**Monthly renewal testing in staging:**

```bash
# Switch to staging
kubectl apply -f obsidian-ingress-tls-staging.yaml
kubectl apply -f couchdb-ingress-tls-staging.yaml

# Force certificate renewal
kubectl delete certificate obsidian-tls couchdb-tls -n obsidian
kubectl delete secret obsidian-tls couchdb-tls -n obsidian

# Wait for renewal
kubectl wait --for=condition=Ready certificate/obsidian-tls -n obsidian --timeout=300s
kubectl wait --for=condition=Ready certificate/couchdb-tls -n obsidian --timeout=300s

# Validate certificates
./validate-ssl-certificates.sh

# Switch back to production if needed
kubectl apply -f obsidian-ingress-tls.yaml
kubectl apply -f couchdb-ingress-tls.yaml
```

#### 2. cert-manager Updates

**Before updating cert-manager:**

1. **Backup current certificates:**
   ```bash
   kubectl get certificates -n obsidian -o yaml > certificates-backup.yaml
   kubectl get secrets -n obsidian --field-selector type=kubernetes.io/tls -o yaml > secrets-backup.yaml
   ```

2. **Test in staging environment first**

3. **Monitor certificate renewal after update**

#### 3. ClusterIssuer Maintenance

**Verify ClusterIssuer configuration:**

```bash
# Check ClusterIssuer status
kubectl get clusterissuer -o wide

# Verify ACME account registration
kubectl describe clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-staging
```

**Update ClusterIssuer email if needed:**

```bash
# Edit ClusterIssuer
kubectl edit clusterissuer letsencrypt-prod
```

### Alerting and Notifications

#### 1. Certificate Expiration Alerts

Set up alerts for certificates expiring within 30 days:

```yaml
# Example Prometheus alert rule
groups:
- name: certificate-expiry
  rules:
  - alert: CertificateExpiringSoon
    expr: (cert_manager_certificate_expiration_timestamp_seconds - time()) / 86400 < 30
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "Certificate {{ $labels.name }} expires soon"
      description: "Certificate {{ $labels.name }} in namespace {{ $labels.namespace }} expires in {{ $value }} days"
```

#### 2. Certificate Request Failures

Monitor for failed certificate requests:

```yaml
# Example Prometheus alert rule
groups:
- name: certificate-failures
  rules:
  - alert: CertificateRequestFailed
    expr: cert_manager_certificate_ready_status{condition="False"} == 1
    for: 15m
    labels:
      severity: critical
    annotations:
      summary: "Certificate request failed"
      description: "Certificate {{ $labels.name }} in namespace {{ $labels.namespace }} failed to be issued"
```

### Best Practices

1. **Always test certificate changes in staging first**
2. **Monitor certificate expiration dates regularly**
3. **Keep cert-manager updated to the latest stable version**
4. **Use separate ClusterIssuers for staging and production**
5. **Implement automated monitoring and alerting**
6. **Document any custom certificate configurations**
7. **Regularly backup certificate configurations**
8. **Test disaster recovery procedures**

## SSL Certificate Validation

For detailed information about SSL certificate validation, including the validation script usage and troubleshooting, see [README-ssl-validation.md](README-ssl-validation.md).

The validation script provides:
- HTTPS connectivity testing
- Certificate validation and expiration checking
- Kubernetes secret verification
- cert-manager integration checks
- Detailed error reporting and troubleshooting guidance

## Additional Resources

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)