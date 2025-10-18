# PostgreSQL PodSecurity Policy Compliance

## Issue
When deploying PostgreSQL in a Kubernetes cluster with "restricted" PodSecurity policies, you may encounter warnings like:

```
Warning: would violate PodSecurity "restricted:latest": 
- allowPrivilegeEscalation != false (container "postgresql" must set securityContext.allowPrivilegeEscalation=false)
- unrestricted capabilities (container "postgresql" must set securityContext.capabilities.drop=["ALL"])
- seccompProfile (pod or container "postgresql" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

## Solution
The PostgreSQL configurations have been updated to comply with the "restricted" PodSecurity policy by adding the required security context settings.

### Changes Made

#### Pod-level Security Context
```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault  # Added for compliance
```

#### Container-level Security Context
```yaml
containers:
- name: postgresql
  image: postgres:15-alpine
  securityContext:
    allowPrivilegeEscalation: false  # Required by restricted policy
    runAsNonRoot: true
    runAsUser: 999
    runAsGroup: 999
    readOnlyRootFilesystem: false    # PostgreSQL needs to write to data directory
    capabilities:
      drop:
      - ALL                          # Drop all capabilities for security
    seccompProfile:
      type: RuntimeDefault           # Use default seccomp profile
```

## Files Updated
- `kubernetes/airflow/postgresql-primary.yaml`
- `kubernetes/airflow/postgresql-standby.yaml`

## Validation
Use the provided validation script to check compliance:

```bash
./kubernetes/airflow/validate-podsecurity.sh
```

## PodSecurity Policy Requirements Met

### ✅ Restricted Policy Compliance
1. **allowPrivilegeEscalation: false** - Prevents privilege escalation
2. **capabilities.drop: [ALL]** - Removes all Linux capabilities
3. **seccompProfile.type: RuntimeDefault** - Uses default seccomp profile
4. **runAsNonRoot: true** - Ensures container runs as non-root user
5. **runAsUser: 999** - Runs as PostgreSQL user (non-zero UID)

### Security Benefits
- **Principle of Least Privilege**: Containers run with minimal permissions
- **Attack Surface Reduction**: No unnecessary capabilities or privileges
- **Compliance**: Meets enterprise security requirements
- **Defense in Depth**: Multiple security layers applied

## Deployment
After applying these fixes, PostgreSQL should deploy without PodSecurity warnings:

```bash
# Deploy PostgreSQL with compliant security context
kubectl apply -f kubernetes/airflow/postgresql-primary.yaml
kubectl apply -f kubernetes/airflow/postgresql-standby.yaml
```

## Troubleshooting

### If You Still See Warnings
1. **Check namespace labels**: Ensure the namespace has correct PodSecurity labels
2. **Verify cluster policy**: Check what PodSecurity policy is enforced
3. **Review admission controllers**: Ensure PodSecurity admission controller is configured

### Common Issues
- **ReadOnlyRootFilesystem**: Set to `false` for PostgreSQL as it needs to write to data directories
- **fsGroup**: Set to 999 to match PostgreSQL user for volume permissions
- **Capabilities**: All capabilities dropped for maximum security

### Validation Commands
```bash
# Check PodSecurity labels on namespace
kubectl get namespace airflow -o yaml | grep -A5 labels

# Verify security context in running pods
kubectl get pod -n airflow -o yaml | grep -A10 securityContext

# Check for security violations
kubectl get events -n airflow | grep -i security
```

## References
- [Kubernetes PodSecurity Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [PostgreSQL Security Best Practices](https://www.postgresql.org/docs/current/security.html)