# Monitoring Stack Module

# Kube Prometheus Stack (includes Prometheus, Alertmanager, and Grafana)
resource "helm_release" "kube_prometheus_stack" {
  count = var.deploy_monitoring ? 1 : 0
  
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = "monitoring"
  
  create_namespace = true
  wait  = true
  timeout = 900 # 15 minutes

  values = [<<EOF
grafana:
  adminPassword: "${var.grafana_admin_password}"
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      k8s-system-resources:
        gnetId: 15759
        revision: 1
        datasource: Prometheus
      k8s-cluster-resources:
        gnetId: 15760
        revision: 1
        datasource: Prometheus
      k8s-node-resources:
        gnetId: 15761
        revision: 1
        datasource: Prometheus
      node-exporter-full:
        gnetId: 1860
        revision: 30
        datasource: Prometheus
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-gateway.monitoring.svc.cluster.local
    - name: Tempo 
      type: tempo
      url: http://tempo.monitoring.svc.cluster.local:3100
      
prometheus:
  prometheusSpec:
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
    resources:
      requests:
        memory: 512Mi
        cpu: 500m
      limits:
        memory: 2Gi
        cpu: 1000m
    remoteWrite:
      - url: http://mimir-nginx.monitoring.svc.cluster.local/api/v1/push
EOF
  ]
}

# Loki Stack for Log Collection
resource "helm_release" "loki" {
  count = var.deploy_monitoring ? 1 : 0
  
  depends_on = [helm_release.kube_prometheus_stack]

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "5.8.9"
  namespace  = "monitoring"
  
  wait  = true
  timeout = 600 # 10 minutes

  values = [<<EOF
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: 'filesystem'
  schemaConfig:
    configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h
  storageConfig:
    boltdb_shipper:
      active_index_directory: /data/loki/boltdb-shipper-active
      cache_location: /data/loki/boltdb-shipper-cache
      cache_ttl: 24h
      shared_store: filesystem
    filesystem:
      directory: /data/loki/chunks

# Use single binary mode for simplicity
singleBinary:
  replicas: 1

# Disable scalable deployment 
read:
  enabled: false
write:
  enabled: false
backend:
  enabled: false

gateway:
  enabled: true
EOF
  ]
}

# Promtail for Log Collection
resource "helm_release" "promtail" {
  count = var.deploy_monitoring ? 1 : 0
  
  depends_on = [helm_release.loki]

  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.15.3"
  namespace  = "monitoring"
  
  wait = true
  timeout = 300 # 5 minutes

  values = [<<EOF
config:
  clients:
    - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
EOF
  ]
}

# Tempo for Distributed Tracing
resource "helm_release" "tempo" {
  count = var.deploy_monitoring ? 1 : 0
  
  depends_on = [helm_release.kube_prometheus_stack]

  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.7.1"  # Updated version
  namespace  = "monitoring"
  
  wait  = true
  timeout = 300 # 5 minutes

  values = [<<EOF
tempo:
  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
  retention: 24h
  reportingEnabled: false

multitenancy:
  enabled: false

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1
    memory: 1Gi
EOF
  ]
}

# Mimir for Scalable Metrics Storage (simplified for small clusters)
resource "helm_release" "mimir" {
  count = var.deploy_monitoring ? 1 : 0
  
  depends_on = [helm_release.kube_prometheus_stack]

  name       = "mimir"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  version    = "4.4.1"
  namespace  = "monitoring"
  
  wait  = true
  timeout = 900 # 15 minutes

  values = [<<EOF
# Simplified deployment for small clusters
nginx:
  service:
    type: ClusterIP

global:
  dnsService: "kube-dns"
  storageClassName: "nfs-client"

resources:
  small:
    limits:
      cpu: 1
      memory: 1Gi
    requests:
      cpu: 100m
      memory: 128Mi

mimir:
  singleBinary:
    enabled: true  # Use single binary mode for simplicity
    replicas: 1
    resources:
      limits:
        cpu: 1
        memory: 2Gi
      requests:
        cpu: 200m
        memory: 512Mi
  
  # Disable complex components for simplicity
  alertmanager:
    enabled: false
  compactor:
    enabled: false
  distributor:
    enabled: false
  ingester:
    enabled: false
  querier:
    enabled: false
  query_frontend:
    enabled: false
  ruler:
    enabled: false
  store_gateway:
    enabled: false

# Use minimal persisted storage
metaMonitoring:
  serviceMonitor:
    enabled: false
  grafanaAgent:
    enabled: false
  dashboards:
    enabled: false
  rules:
    enabled: false
EOF
  ]
} 