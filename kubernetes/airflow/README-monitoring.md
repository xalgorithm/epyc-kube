# Airflow Monitoring Configuration

This document describes the Prometheus metrics collection setup for the Airflow Kubernetes deployment.

## Overview

The monitoring configuration implements Requirements 3.1 and 3.7 by providing comprehensive metrics collection for all Airflow components:

- **StatsD Exporter**: Collects Airflow application metrics via StatsD protocol
- **PostgreSQL Exporter**: Collects database performance and Airflow-specific metrics
- **Redis Exporter**: Collects queue metrics and Redis performance data
- **ServiceMonitors**: Enable Prometheus to scrape all metrics endpoints

## Components

### 1. StatsD Exporter

**File**: `airflow-statsd-exporter.yaml`

Collects Airflow application metrics by receiving StatsD metrics from Airflow components and converting them to Prometheus format.

**Key Features**:
- Receives StatsD metrics on UDP port 9125
- Exposes Prometheus metrics on HTTP port 9102
- Custom mapping configuration for Airflow-specific metrics
- Includes DAG execution, task duration, scheduler, and executor metrics

**Metrics Examples**:
- `airflow_dag_task_duration_seconds`: Task execution duration
- `airflow_scheduler_tasks_running`: Number of running tasks
- `airflow_executor_queued_tasks`: Number of queued tasks
- `airflow_task_instance_finished_total`: Task completion counters

### 2. PostgreSQL Exporter

**File**: `postgresql-exporter.yaml`

Collects database metrics including both standard PostgreSQL metrics and Airflow-specific database queries.

**Key Features**:
- Standard PostgreSQL performance metrics
- Custom Airflow queries for DAG runs, task instances, and durations
- Database connection pool monitoring
- Replication lag monitoring for HA setup

**Metrics Examples**:
- `pg_stat_database_*`: Database statistics
- `airflow_dag_runs`: DAG run counts by state
- `airflow_task_instances`: Task instance counts by state
- `airflow_connection_pool_utilization_percent`: Connection pool usage

### 3. Redis Exporter

**File**: `redis-servicemonitor.yaml` (updated)

Collects Redis metrics for queue monitoring and performance.

**Key Features**:
- Redis server performance metrics
- Queue depth and processing metrics
- Memory usage and connection statistics
- Celery-specific queue metrics

**Metrics Examples**:
- `redis_connected_clients`: Number of connected clients
- `redis_used_memory_bytes`: Memory usage
- `redis_commands_processed_total`: Command processing statistics

### 4. ServiceMonitors

**File**: `airflow-servicemonitors.yaml`

Configures Prometheus to scrape metrics from all Airflow components.

**Components Monitored**:
- Airflow Webserver
- Airflow Scheduler
- Airflow Workers
- Flower (Celery monitoring)
- StatsD Exporter
- PostgreSQL Exporter
- Redis Exporter

## Deployment

### Prerequisites

1. Kubernetes cluster with Airflow deployed
2. Prometheus Operator (kube-prometheus-stack) installed
3. HashiCorp Vault with database credentials (for PostgreSQL exporter)

### Installation Steps

1. **Deploy monitoring components**:
   ```bash
   ./deploy-airflow-monitoring.sh
   ```

2. **Configure PostgreSQL exporter credentials**:
   ```bash
   ./setup-postgresql-exporter-credentials.sh
   ```

3. **Update Airflow deployment** with StatsD configuration:
   ```bash
   helm upgrade airflow apache-airflow/airflow -f airflow-values.yaml -n airflow
   ```

4. **Verify deployment**:
   ```bash
   ./test-airflow-monitoring.sh
   ```

### Manual Deployment

If you prefer manual deployment:

```bash
# Deploy StatsD exporter
kubectl apply -f airflow-statsd-exporter.yaml

# Deploy ServiceMonitors
kubectl apply -f airflow-servicemonitors.yaml

# Deploy PostgreSQL exporter
kubectl apply -f postgresql-exporter.yaml

# Update Redis exporter
kubectl apply -f redis-servicemonitor.yaml
```

## Configuration

### StatsD Configuration in Airflow

The Airflow values file includes StatsD configuration:

```yaml
# StatsD configuration for monitoring
statsd:
  enabled: true
  host: airflow-statsd-exporter
  port: 9125

# Airflow configuration
airflow:
  config:
    AIRFLOW__METRICS__STATSD_ON: "True"
    AIRFLOW__METRICS__STATSD_HOST: "airflow-statsd-exporter"
    AIRFLOW__METRICS__STATSD_PORT: "9125"
    AIRFLOW__METRICS__STATSD_PREFIX: "airflow"
```

### PostgreSQL Exporter Queries

Custom queries are configured to collect Airflow-specific metrics:

- **DAG Runs**: Count of DAG runs by state in last 24 hours
- **Task Instances**: Count of task instances by state and DAG
- **Task Duration**: Average and maximum task execution times
- **Active DAGs**: Number of active and unpaused DAGs
- **Connection Pool**: Database connection utilization

### ServiceMonitor Labels

All ServiceMonitors include labels for Prometheus discovery:

```yaml
labels:
  prometheus: kube-prometheus-stack-prometheus
  release: kube-prometheus-stack
```

## Verification

### Check Deployments

```bash
kubectl get pods -n airflow -l tier=monitoring
kubectl get servicemonitors -n airflow
```

### Test Metrics Endpoints

```bash
# StatsD Exporter
kubectl port-forward -n airflow service/airflow-statsd-exporter 9102:9102
curl http://localhost:9102/metrics

# PostgreSQL Exporter
kubectl port-forward -n airflow service/postgresql-exporter 9187:9187
curl http://localhost:9187/metrics

# Redis Exporter
kubectl port-forward -n airflow service/redis-metrics 9121:9121
curl http://localhost:9121/metrics
```

### Check Prometheus Targets

1. Access Prometheus UI
2. Go to Status → Targets
3. Look for Airflow-related targets in the `airflow` namespace

## Troubleshooting

### Common Issues

1. **ServiceMonitors not discovered**:
   - Check Prometheus operator labels
   - Verify namespace selector in Prometheus configuration
   - Ensure ServiceMonitor labels match Prometheus selector

2. **PostgreSQL exporter connection errors**:
   - Verify database credentials in secret
   - Check network connectivity to PostgreSQL
   - Review PostgreSQL logs for connection issues

3. **StatsD metrics not appearing**:
   - Ensure Airflow is configured to send StatsD metrics
   - Check StatsD exporter logs for received metrics
   - Verify network connectivity between Airflow and exporter

4. **Redis exporter authentication errors**:
   - Verify Redis password in secret
   - Check Redis configuration for authentication
   - Review Redis exporter logs

### Log Analysis

```bash
# Check exporter logs
kubectl logs -n airflow deployment/airflow-statsd-exporter
kubectl logs -n airflow deployment/postgresql-exporter
kubectl logs -n airflow deployment/redis-exporter

# Check Airflow logs for StatsD
kubectl logs -n airflow deployment/airflow-scheduler | grep -i statsd
kubectl logs -n airflow deployment/airflow-webserver | grep -i statsd
```

## Security Considerations

1. **Network Policies**: Ensure monitoring traffic is allowed
2. **RBAC**: ServiceMonitors require appropriate permissions
3. **Secrets**: Database credentials are stored in Kubernetes secrets
4. **TLS**: Consider enabling TLS for metrics endpoints in production

## Next Steps

After successful deployment:

1. **Create Grafana Dashboards**: Import or create dashboards for visualization
2. **Set up Alerting**: Configure PrometheusRules for critical alerts
3. **Performance Tuning**: Adjust scrape intervals and retention based on needs
4. **Custom Metrics**: Add application-specific metrics as needed

## Related Files

- `airflow-values.yaml`: Airflow Helm values with StatsD configuration
- `deploy-airflow-monitoring.sh`: Deployment script
- `test-airflow-monitoring.sh`: Testing and verification script
- `setup-postgresql-exporter-credentials.sh`: Credential configuration script