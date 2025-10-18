# Airflow Storage Configuration

This directory contains the persistent storage configuration for Apache Airflow deployment on Kubernetes, implementing requirements 2.2, 2.3, and 2.6 from the Airflow Kubernetes deployment specification.

## Overview

The storage configuration provides:
- **Persistent storage for DAGs** with ReadWriteMany access mode
- **Persistent storage for logs** with ReadWriteMany access mode  
- **Persistent storage for configuration** with ReadWriteMany access mode
- **Storage monitoring and alerting** for capacity and performance
- **Integration with existing NFS infrastructure**

## Components

### Storage Resources

#### PersistentVolumeClaims
- `airflow-dags-pvc` - 50Gi storage for DAG files
- `airflow-logs-pvc` - 200Gi storage for task logs
- `airflow-config-pvc` - 10Gi storage for configuration files

All PVCs use:
- **Access Mode**: ReadWriteMany (required for multi-pod access)
- **Storage Class**: nfs-client (existing NFS infrastructure)
- **Reclaim Policy**: Retain (data preservation)

#### Storage Class
- Uses existing `nfs-client` storage class
- Integrates with established NFS infrastructure
- Supports volume expansion for future growth

### Monitoring Components

#### Storage Exporter
- **Deployment**: `airflow-storage-exporter`
- **Image**: prom/node-exporter:v1.6.1
- **Metrics**: Filesystem usage, I/O statistics, device errors
- **Endpoints**: Exposes metrics on port 9100

#### ServiceMonitor
- **Resource**: `airflow-storage-monitor`
- **Scrape Interval**: 30 seconds
- **Integration**: Prometheus monitoring stack

#### Alerting Rules
- **Resource**: `airflow-storage-alerts`
- **Critical Alerts**: Storage >90% full, PVC lost, device errors
- **Warning Alerts**: Storage >80% full, high I/O wait, rapid growth
- **Performance Alerts**: I/O bottlenecks, read/write errors

## Files

| File | Purpose |
|------|---------|
| `airflow-storage.yaml` | PVC definitions and storage class configuration |
| `airflow-storage-monitoring.yaml` | Storage monitoring deployment and service |
| `airflow-storage-alerts.yaml` | PrometheusRule for storage alerting |
| `deploy-airflow-storage.sh` | Deployment script for all storage components |
| `test-airflow-storage.sh` | Validation script for storage functionality |
| `README-storage.md` | This documentation file |

## Deployment

### Prerequisites
- Kubernetes cluster with kubectl access
- Existing `nfs-client` storage class
- Prometheus monitoring stack deployed
- `airflow` namespace (created automatically)

### Deploy Storage
```bash
# Deploy all storage components
./deploy-airflow-storage.sh

# Validate deployment
./test-airflow-storage.sh
```

### Manual Deployment
```bash
# Create namespace
kubectl create namespace airflow

# Apply storage configuration
kubectl apply -f airflow-storage.yaml

# Apply monitoring
kubectl apply -f airflow-storage-monitoring.yaml

# Apply alerting rules
kubectl apply -f airflow-storage-alerts.yaml
```

## Validation

The test script validates:
- ✅ PVC creation and binding
- ✅ ReadWriteMany access mode
- ✅ Correct storage class assignment
- ✅ Proper capacity allocation
- ✅ Monitoring component deployment
- ✅ Alerting rule configuration
- ✅ Functional storage access
- ✅ Multi-pod concurrent access

## Storage Layout

```
/airflow/
├── dags/          # DAG files (50Gi, ReadWriteMany)
├── logs/          # Task execution logs (200Gi, ReadWriteMany)
└── config/        # Configuration files (10Gi, ReadWriteMany)
```

## Monitoring Metrics

### Key Metrics Collected
- `node_filesystem_avail_bytes` - Available storage space
- `node_filesystem_size_bytes` - Total storage capacity
- `node_filesystem_device_error_total` - Storage device errors
- `node_cpu_seconds_total{mode="iowait"}` - I/O wait time
- `kube_persistentvolumeclaim_status_phase` - PVC status

### Grafana Dashboards
Storage metrics are available in Grafana dashboards:
- **Node Exporter Full** - System-level storage metrics
- **Kubernetes Persistent Volumes** - PVC status and usage
- **Custom Airflow Storage** - Application-specific metrics

## Alerting

### Critical Alerts (Immediate Action Required)
- **AirflowStorageCriticallyFull** - Storage >90% full
- **AirflowPVCLost** - PVC in Lost state
- **AirflowStorageReadErrors** - Storage device errors

### Warning Alerts (Monitor Closely)
- **AirflowStorageWarning** - Storage >80% full
- **AirflowPVCPending** - PVC stuck in Pending state
- **AirflowStorageHighIOWait** - High I/O wait times
- **AirflowLogGrowthRateHigh** - Rapid log growth

### Alert Routing
Alerts are routed through existing AlertManager configuration to:
- ntfy notifications for immediate alerts
- Email notifications for warning alerts
- Slack integration for team notifications

## Troubleshooting

### Common Issues

#### PVC Stuck in Pending
```bash
# Check storage class availability
kubectl get storageclass nfs-client

# Check PVC events
kubectl describe pvc airflow-dags-pvc -n airflow

# Verify NFS server connectivity
kubectl get pv
```

#### Storage Full
```bash
# Check current usage
kubectl exec -n airflow deployment/airflow-storage-exporter -- df -h

# Clean up old logs (if safe)
kubectl exec -n airflow -it <airflow-pod> -- find /opt/airflow/logs -name "*.log" -mtime +30 -delete

# Expand PVC (if storage class supports it)
kubectl patch pvc airflow-logs-pvc -n airflow -p '{"spec":{"resources":{"requests":{"storage":"300Gi"}}}}'
```

#### Monitoring Not Working
```bash
# Check exporter status
kubectl get deployment airflow-storage-exporter -n airflow
kubectl logs deployment/airflow-storage-exporter -n airflow

# Verify ServiceMonitor
kubectl get servicemonitor airflow-storage-monitor -n airflow -o yaml

# Check Prometheus targets
# Access Prometheus UI and verify airflow-storage-exporter target
```

## Security Considerations

### Access Control
- Storage exporter runs with minimal privileges
- ServiceAccount with restricted RBAC permissions
- No root access required for monitoring

### Data Protection
- PVCs use Retain reclaim policy
- NFS storage provides network-level security
- Monitoring data doesn't expose sensitive content

### Network Security
- Storage exporter only exposes metrics endpoint
- No external network access required
- Integrates with existing network policies

## Capacity Planning

### Current Allocation
- **DAGs**: 50Gi (estimated for 10,000+ DAG files)
- **Logs**: 200Gi (estimated for 6 months of logs)
- **Config**: 10Gi (estimated for plugins and configurations)

### Growth Projections
- **Log Growth**: ~1GB per day (adjust based on workload)
- **DAG Growth**: ~100MB per month (depends on development)
- **Config Growth**: Minimal (~10MB per month)

### Scaling Recommendations
- Monitor growth trends via Grafana dashboards
- Set up predictive alerts for capacity planning
- Consider log rotation and archival policies
- Plan for 20% buffer above projected usage

## Integration with Airflow

### Helm Chart Configuration
When deploying Airflow with Helm, reference these PVCs:

```yaml
# values.yaml
dags:
  persistence:
    enabled: true
    existingClaim: airflow-dags-pvc
    
logs:
  persistence:
    enabled: true
    existingClaim: airflow-logs-pvc

config:
  persistence:
    enabled: true
    existingClaim: airflow-config-pvc
```

### Volume Mounts
Standard mount points for Airflow components:
- **Scheduler**: `/opt/airflow/dags` (DAGs), `/opt/airflow/logs` (logs)
- **Webserver**: `/opt/airflow/dags` (DAGs), `/opt/airflow/logs` (logs)
- **Workers**: `/opt/airflow/dags` (DAGs), `/opt/airflow/logs` (logs)

## Backup and Recovery

### Backup Strategy
- **NFS-level backups** - Handled by NFS infrastructure
- **Application-level backups** - DAG files in Git repository
- **Log archival** - Automated cleanup and archival to object storage

### Recovery Procedures
1. **PVC Recovery** - Restore from NFS snapshots
2. **DAG Recovery** - Restore from Git repository
3. **Log Recovery** - Restore from archived storage (if needed)

## Performance Optimization

### NFS Tuning
- Use NFSv4 for better performance
- Configure appropriate rsize/wsize parameters
- Consider NFS caching for read-heavy workloads

### Kubernetes Optimization
- Use local SSD for temporary storage when possible
- Configure appropriate resource limits
- Monitor I/O patterns and adjust accordingly

## Compliance and Governance

### Data Retention
- Logs retained for 6 months (configurable)
- DAGs retained indefinitely (version controlled)
- Configuration changes tracked and audited

### Audit Trail
- All storage access logged via Kubernetes audit logs
- File system changes tracked via monitoring
- Access patterns monitored for anomalies

---

For questions or issues, refer to the main Airflow deployment documentation or contact the platform team.