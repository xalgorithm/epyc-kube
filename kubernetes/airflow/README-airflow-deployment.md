# Airflow Helm Deployment - High Availability Configuration

This document describes the implementation of Task 5: Deploy Airflow using Helm chart with HA configuration.

## Overview

This deployment implements a production-ready Apache Airflow installation on Kubernetes using the official Airflow Helm chart with high availability, comprehensive resource management, and enterprise-grade configuration.

## Requirements Implemented

- **Requirement 1.1**: Multiple replicas for webserver component (2 replicas)
- **Requirement 1.2**: Multiple replicas for scheduler component (2 replicas with leader election)
- **Requirement 1.3**: Automatic pod restart and service availability for webserver
- **Requirement 1.4**: Automatic pod restart without workflow state loss for scheduler
- **Requirement 5.4**: CeleryKubernetesExecutor for hybrid task execution

## Architecture

### High Availability Components

#### Webserver (2 replicas)
- **Resources**: 2 CPU cores, 4Gi memory per pod
- **Health Checks**: Liveness and readiness probes on `/health`
- **Load Balancing**: Kubernetes service distributes traffic
- **Failover**: Automatic pod restart on failure

#### Scheduler (2 replicas with leader election)
- **Resources**: 2 CPU cores, 4Gi memory per pod
- **Leader Election**: Database-based coordination prevents split-brain
- **Health Checks**: Liveness probes for automatic restart
- **State Persistence**: Workflow state maintained in PostgreSQL

#### Workers (CeleryKubernetesExecutor)
- **Initial Replicas**: 2 (will be managed by HPA in task 8)
- **Resources**: 1 CPU core, 2Gi memory per pod
- **Hybrid Execution**: Supports both Celery and Kubernetes executors
- **Auto-scaling**: Prepared for horizontal pod autoscaling

## Files Created

### 1. `airflow-values.yaml`
Comprehensive Helm values file with:
- HA configuration for all components
- Resource limits and requests
- Health check configuration
- External database and Redis integration
- Security context configuration
- Persistent volume configuration

### 2. `deploy-airflow.sh`
Deployment script that:
- Validates prerequisites (PostgreSQL, Redis, storage)
- Adds Airflow Helm repository
- Validates Helm values
- Deploys/upgrades Airflow release
- Verifies deployment success
- Provides connection information

### 3. `test-airflow-deployment.sh`
Comprehensive test suite that validates:
- HA replica counts
- Health check configuration
- Resource limit configuration
- Pod status and connectivity
- Database and Redis connectivity
- Service account and PVC configuration

## Prerequisites

Before deploying Airflow, ensure the following components are already deployed:

1. **PostgreSQL Database** (Task 1)
   - Primary and standby instances
   - Service: `postgresql-primary`
   - Secret: `postgresql-secret`

2. **Redis Cluster** (Task 2)
   - Redis Sentinel cluster
   - Service: `redis`
   - Secret: `redis-secret`

3. **Persistent Storage** (Task 3)
   - DAGs PVC: `airflow-dags-pvc`
   - Logs PVC: `airflow-logs-pvc`

4. **RBAC Configuration** (Task 4)
   - Namespace: `airflow`
   - Service Account: `airflow-scheduler`

## Deployment Instructions

### 1. Deploy Airflow
```bash
cd kubernetes/airflow
./deploy-airflow.sh
```

### 2. Verify Deployment
```bash
./test-airflow-deployment.sh
```

### 3. Access Airflow Webserver
```bash
# Port forward to access locally
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow

# Open browser to http://localhost:8080
# Default credentials: admin/admin (if not using external auth)
```

## Configuration Details

### Executor Configuration
- **Type**: CeleryKubernetesExecutor
- **Celery Workers**: For long-running tasks
- **Kubernetes Workers**: For short-lived, isolated tasks
- **Queue Management**: Redis-based task queuing

### Resource Configuration
| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Webserver | 1000m       | 2000m     | 2Gi            | 4Gi          |
| Scheduler | 1000m       | 2000m     | 2Gi            | 4Gi          |
| Worker    | 500m        | 1000m     | 1Gi            | 2Gi          |
| Flower    | 100m        | 200m      | 128Mi          | 256Mi        |

### Health Check Configuration
- **Liveness Probes**: Automatic restart on failure
- **Readiness Probes**: Traffic routing control
- **Startup Probes**: Graceful initialization handling

### Security Configuration
- **Non-root execution**: All pods run as user 50000
- **Security context**: Restricted pod security standards
- **Service accounts**: Dedicated accounts with minimal RBAC

## Monitoring Integration

The deployment is prepared for monitoring integration (Task 10):
- StatsD exporter enabled for Prometheus metrics
- Health endpoints exposed for monitoring
- Structured logging configuration

## Next Steps

After successful deployment, proceed with:

1. **Task 6**: Integrate HashiCorp Vault for secrets management
2. **Task 7**: Configure Ingress and TLS certificates
3. **Task 8**: Set up horizontal pod autoscaling for workers
4. **Task 9**: Implement network policies for security
5. **Task 10**: Configure Prometheus metrics collection

## Troubleshooting

### Common Issues

#### Pods Not Starting
```bash
# Check pod status
kubectl get pods -n airflow -l app.kubernetes.io/name=airflow

# Check pod logs
kubectl logs -n airflow deployment/airflow-scheduler
kubectl logs -n airflow deployment/airflow-webserver
```

#### Database Connection Issues
```bash
# Test database connectivity
kubectl exec -n airflow deployment/airflow-scheduler -- airflow db check

# Check PostgreSQL status
kubectl get pods -n airflow -l app=postgresql
```

#### Redis Connection Issues
```bash
# Test Redis connectivity
kubectl exec -n airflow deployment/airflow-scheduler -- \
  python -c "import redis; r=redis.Redis(host='redis', port=6379, password='airflow-redis-2024'); print(r.ping())"
```

### Logs and Debugging
```bash
# View all Airflow logs
kubectl logs -n airflow -l app.kubernetes.io/name=airflow --tail=100

# Check Helm release status
helm status airflow -n airflow

# Describe problematic pods
kubectl describe pod <pod-name> -n airflow
```

## Validation Checklist

- [ ] Webserver has 2 replicas running
- [ ] Scheduler has 2 replicas running
- [ ] Workers are running and registered
- [ ] Database connectivity working
- [ ] Redis connectivity working
- [ ] Health checks responding
- [ ] Resource limits configured
- [ ] Persistent volumes mounted
- [ ] Services accessible

## Security Considerations

- Secrets are currently hardcoded (will be replaced with Vault in Task 6)
- Network policies not yet implemented (Task 9)
- TLS not yet configured (Task 7)
- Authentication using default admin user (will be integrated with external auth in Task 15)

## Performance Notes

- Resource requests ensure guaranteed resources
- Resource limits prevent resource exhaustion
- Multiple replicas provide load distribution
- Health checks enable fast failure detection
- Leader election prevents scheduler conflicts