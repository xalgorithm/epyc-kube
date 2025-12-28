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

kubeEtcd:
  enabled: true
  service:
    enabled: false # We will manage this manually for k3s
  serviceMonitor:
    scheme: http # k3s uses http by default for etcd metrics unless configured otherwise
EOF
  ]
}

# Manual etcd service for K3s (as it doesn't run etcd as pod)
resource "kubernetes_service" "k3s_etcd" {
  count = var.deploy_monitoring ? 1 : 0
  
  metadata {
    name      = "kube-prometheus-stack-kube-etcd-manual"
    namespace = "kube-system"
    labels = {
      app     = "kube-prometheus-stack-kube-etcd"
      release = "kube-prometheus-stack"
    }
  }

  spec {
    port {
      name        = "http-metrics"
      port        = 2381
      target_port = 2381
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_endpoints" "k3s_etcd" {
  count = var.deploy_monitoring ? 1 : 0

  metadata {
    name      = "kube-prometheus-stack-kube-etcd-manual"
    namespace = "kube-system"
    labels = {
      app     = "kube-prometheus-stack-kube-etcd"
      release = "kube-prometheus-stack"
    }
  }

  subset {
    address {
      ip = "192.168.100.10" # gimli private IP
    }
    port {
      name = "http-metrics"
      port = 2381
    }
  }
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

# Mimir for Scalable Metrics Storage
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
# Fixed configuration for the cluster environment
nginx:
  enabled: true
  service:
    type: ClusterIP
  configOverride: |
    worker_processes  5;
    error_log  /dev/stderr error;
    pid        /tmp/nginx.pid;
    worker_rlimit_nofile 8192;
    events {
      worker_connections  4096;
    }
    http {
      client_body_temp_path /tmp/client_temp;
      proxy_temp_path       /tmp/proxy_temp_path;
      fastcgi_temp_path     /tmp/fastcgi_temp;
      uwsgi_temp_path       /tmp/uwsgi_temp;
      scgi_temp_path        /tmp/scgi_temp;
      default_type application/octet-stream;
      access_log   /dev/stderr;
      sendfile     on;
      tcp_nopush   on;
      resolver 10.43.0.10;
      map $http_x_scope_orgid $ensured_x_scope_orgid {
        default $http_x_scope_orgid;
        "" "anonymous";
      }
      server {
        listen 8080;
        location = / { return 200 'OK'; }
        proxy_set_header X-Scope-OrgID $ensured_x_scope_orgid;
        location /distributor {
          set $distributor mimir-distributor-headless.monitoring.svc.cluster.local;
          proxy_pass http://$distributor:8080$request_uri;
        }
        location = /api/v1/push {
          set $distributor mimir-distributor-headless.monitoring.svc.cluster.local;
          proxy_pass http://$distributor:8080$request_uri;
        }
        location /prometheus {
          set $query_frontend mimir-query-frontend.monitoring.svc.cluster.local;
          proxy_pass http://$query_frontend:8080$request_uri;
        }
      }
    }

global:
  dnsService: "kube-dns"
  storageClassName: "nfs-client"

mimir:
  structuredConfig:
    common:
      storage:
        backend: s3
        s3:
          endpoint: minio.monitoring:9000
          bucket_name: mimir
          access_key_id: mimir
          secret_access_key: mimir
          insecure: true
    config_file: /etc/mimir/mimir.yaml

# Re-enabling components to match the current Distributed deployment
mimir_distributed:
  enabled: true

ingester:
  replicas: 3
  zoneAwareness:
    enabled: true
querier:
  replicas: 2
query_frontend:
  replicas: 1
EOF
  ]
} 