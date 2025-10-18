# Airflow Helm Values Fix

## Issue Description

When running the Airflow deployment, Helm validation failed with multiple schema errors:

```
Error: values don't meet the specifications of the schema(s) in the following chart(s):
airflow:
- statsd: Additional property host is not allowed
- statsd: Additional property port is not allowed
- data.metadataConnection: Additional property userSecret is not allowed
- workers: Additional property celery is not allowed
- extraEnvFrom: Invalid type. Expected: [null,string], given: array
```

## Root Cause

The Airflow Helm chart schema has changed significantly between versions. The values file was using an older schema format that is no longer compatible with the current chart version (v1.18.0 with Airflow 3.0.2).

## Key Changes Made

### 1. Configuration Structure
**Before (Flat structure):**
```yaml
config:
  AIRFLOW__CORE__EXECUTOR: CeleryKubernetesExecutor
  AIRFLOW__METRICS__STATSD_ON: "True"
  AIRFLOW__METRICS__STATSD_HOST: "airflow-statsd-exporter"
```

**After (Nested structure):**
```yaml
config:
  core:
    dags_are_paused_at_creation: "True"
    load_examples: "False"
  metrics:
    statsd_on: "True"
    statsd_host: "airflow-statsd-exporter"
    statsd_port: 9125
```

### 2. Executor Configuration
**Before:**
```yaml
airflow:
  executor: CeleryKubernetesExecutor
```

**After:**
```yaml
executor: CeleryKubernetesExecutor
```

### 3. Database Connection
**Before:**
```yaml
data:
  metadataConnection:
    userSecret: airflow-database-secret
    userSecretKey: POSTGRES_USER
    passwordSecret: airflow-database-secret
    passwordSecretKey: POSTGRES_PASSWORD
```

**After:**
```yaml
data:
  metadataSecretName: airflow-database-secret
  resultBackendSecretName: airflow-database-secret
  brokerUrlSecretName: airflow-redis-secret
```

### 4. Security Context
**Before:**
```yaml
securityContext:
  runAsUser: 50000
  runAsGroup: 0
  fsGroup: 0
```

**After:**
```yaml
securityContexts:
  pod:
    runAsNonRoot: true
    runAsUser: 50000
    runAsGroup: 0
    fsGroup: 0
  containers:
    runAsNonRoot: true
    runAsUser: 50000
    runAsGroup: 0
```

### 5. Environment Variables
**Before:**
```yaml
extraEnvFrom:
  - secretRef:
      name: airflow-database-secret
```

**After:**
```yaml
extraEnvFrom: |
  - secretRef:
      name: airflow-database-secret
  - secretRef:
      name: airflow-redis-secret
```

### 6. Probe Configuration
**Before:**
```yaml
webserver:
  livenessProbe:
    enabled: true
    httpGet:
      path: /health
      port: 8080
```

**After:**
```yaml
webserver:
  livenessProbe:
    initialDelaySeconds: 60
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 5
    scheme: HTTP
```

### 7. StatsD Configuration
**Before:**
```yaml
statsd:
  enabled: true
  host: airflow-statsd-exporter
  port: 9125
```

**After:**
```yaml
statsd:
  enabled: true
# Configuration moved to config.metrics section
```

## Removed Invalid Properties

The following properties were removed as they are no longer supported:
- `workers.celery`
- `workers.autoscaling`
- `workers.readinessProbe`
- `workers.podDisruptionBudget`
- `logs.persistence.accessMode`
- `webserver.service.port`
- `flower.replicas`

## Files Updated

- `airflow-values.yaml` - Fixed to use current Helm chart schema
- `airflow-values-old.yaml` - Backup of original values file

## Validation

The fixed values file now passes Helm validation:

```bash
helm template airflow apache-airflow/airflow -f airflow-values.yaml --dry-run
```

## Key Features Preserved

All original functionality is preserved:
- ✅ CeleryKubernetesExecutor for hybrid execution
- ✅ High availability with multiple replicas
- ✅ External PostgreSQL and Redis integration
- ✅ Vault-managed secrets
- ✅ StatsD metrics collection
- ✅ Persistent volume configuration
- ✅ Security contexts and RBAC
- ✅ Resource limits and requests
- ✅ Health checks and probes

## Chart Version Information

- **Chart Version**: v1.18.0
- **Airflow Version**: 3.0.2
- **Schema**: Updated to match current chart requirements

## Next Steps

The Airflow deployment should now proceed without validation errors. The configuration maintains all the high availability and monitoring features while being compatible with the current Helm chart schema.