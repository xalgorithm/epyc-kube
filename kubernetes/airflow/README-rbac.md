# Airflow RBAC Configuration

This directory contains the Role-Based Access Control (RBAC) configuration for the Airflow deployment on Kubernetes.

## Overview

The RBAC configuration implements security best practices with minimal required permissions for each Airflow component, following the principle of least privilege.

## Components

### Namespace
- **Name**: `airflow`
- **Pod Security Standards**: Restricted mode enforced
- **Labels**: Properly labeled for monitoring and management

### Service Accounts

1. **airflow-webserver**: For the Airflow web UI component
2. **airflow-scheduler**: For the Airflow scheduler component
3. **airflow-worker**: For Airflow worker pods
4. **airflow-triggerer**: For the Airflow triggerer component

### Roles and Permissions

#### Scheduler Role (`airflow-scheduler`)
- **Pod Management**: Create, delete, get, list, patch, update, watch pods (for KubernetesExecutor)
- **Pod Logs**: Get and list pod logs
- **Pod Exec**: Create and get pod exec sessions
- **ConfigMaps**: Read access for DAG configuration
- **Secrets**: Read access for connections and variables
- **Services**: Read access for service discovery
- **Events**: Create and patch events for logging

#### Worker Role (`airflow-worker`)
- **ConfigMaps**: Read access for task configuration
- **Secrets**: Read access for connections
- **Pods**: Read access for self-inspection
- **Events**: Create and patch events for logging

#### Webserver Role (`airflow-webserver`)
- **ConfigMaps**: Read access for configuration display
- **Secrets**: Read access for connection testing
- **Pods**: Read access for log viewing and task monitoring
- **Pod Logs**: Get and list pod logs
- **Services**: Read access for health checks

#### Triggerer Role (`airflow-triggerer`)
- **ConfigMaps**: Read access for configuration
- **Secrets**: Read access for connections
- **Events**: Create and patch events for logging

### Network Policies

The configuration includes comprehensive network policies that implement a zero-trust network model:

#### Default Deny
- All ingress traffic is denied by default

#### Specific Allow Rules
- **Webserver**: Ingress from Traefik ingress controller and monitoring
- **Scheduler**: Egress to PostgreSQL, Redis, workers, DNS, and HTTPS
- **Workers**: Egress to PostgreSQL, Redis, DNS, and HTTPS
- **Database**: Ingress from Airflow components and monitoring
- **Redis**: Ingress from Airflow components and monitoring

## Files

- `airflow-namespace-rbac.yaml`: Main RBAC configuration with namespace, service accounts, roles, and role bindings
- `airflow-security-policies.yaml`: Network policies for enhanced security
- `deploy-airflow-rbac.sh`: Deployment script for applying the configuration
- `README-rbac.md`: This documentation file

## Deployment

### Prerequisites
- Kubernetes cluster with RBAC enabled
- kubectl configured with cluster admin permissions
- CNI that supports NetworkPolicies (for network security)

### Deploy RBAC Configuration

```bash
# Deploy the RBAC configuration
./deploy-airflow-rbac.sh deploy

# Check deployment status
./deploy-airflow-rbac.sh status

# Clean up (if needed)
./deploy-airflow-rbac.sh cleanup
```

### Verification

After deployment, verify the configuration:

```bash
# Check namespace
kubectl get namespace airflow

# Check service accounts
kubectl get serviceaccounts -n airflow -l app.kubernetes.io/name=airflow

# Check roles
kubectl get roles -n airflow -l app.kubernetes.io/name=airflow

# Check role bindings
kubectl get rolebindings -n airflow -l app.kubernetes.io/name=airflow

# Check network policies
kubectl get networkpolicies -n airflow
```

## Security Features

### Pod Security Standards
- **Enforcement Level**: Restricted
- **Audit Level**: Restricted
- **Warning Level**: Restricted

This ensures all pods in the namespace must comply with the most restrictive security standards.

### Minimal Permissions
Each service account has only the minimum permissions required for its function:
- No cluster-wide permissions
- No write access to sensitive resources unless required
- Read-only access where possible

### Network Segmentation
- Default deny all ingress traffic
- Explicit allow rules for required communication
- Monitoring access properly configured
- DNS resolution allowed for all components

## Integration with Helm Chart

When deploying Airflow using the official Helm chart, configure it to use these service accounts:

```yaml
serviceAccount:
  create: false
  name: airflow-webserver

scheduler:
  serviceAccount:
    create: false
    name: airflow-scheduler

workers:
  serviceAccount:
    create: false
    name: airflow-worker

triggerer:
  serviceAccount:
    create: false
    name: airflow-triggerer
```

## Troubleshooting

### Common Issues

1. **NetworkPolicy not working**: Ensure your CNI supports NetworkPolicies
2. **Permission denied**: Check that the correct service account is being used
3. **Pod creation fails**: Verify Pod Security Standards compliance

### Debug Commands

```bash
# Check service account permissions
kubectl auth can-i --list --as=system:serviceaccount:airflow:airflow-scheduler -n airflow

# Check network policy effects
kubectl describe networkpolicy -n airflow

# Check pod security policy violations
kubectl get events -n airflow --field-selector type=Warning
```

## Requirements Compliance

This configuration addresses the following requirements:

- **4.1**: RBAC authentication enabled with proper service accounts
- **4.7**: Network policies and Pod Security Standards for enhanced security
- **7.5**: Integration with existing Kubernetes security policies

## Next Steps

After deploying the RBAC configuration:

1. Deploy the Airflow Helm chart with the configured service accounts
2. Verify that all components can communicate properly
3. Test the network policies by attempting unauthorized connections
4. Monitor the security audit logs for any violations