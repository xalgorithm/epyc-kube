# Monitoring Module

This module handles the deployment of the observability stack for Kubernetes.

## Features

- Deploys Prometheus for metrics collection
- Sets up Grafana for visualization
- Configures Loki for log aggregation
- Installs Tempo for distributed tracing
- Includes Mimir for long-term metrics storage

## Usage

```hcl
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.deploy_kubernetes ? 1 : 0
  
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }
  
  deploy_monitoring      = true
  kubeconfig_path        = "${path.module}/kubeconfig.yaml"
  grafana_admin_password = "********"
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| deploy_monitoring | Whether to deploy monitoring stack | bool | Yes |
| kubeconfig_path | Path to the kubeconfig file | string | Yes |
| grafana_admin_password | Grafana admin password | string | Yes |

## Outputs

| Name | Description |
|------|-------------|
| monitoring_namespace | Namespace for monitoring components |
| grafana_service_name | Grafana service name |
| prometheus_service_name | Prometheus service name |
| loki_gateway_service | Loki gateway service name |
| tempo_service_name | Tempo service name |
| mimir_service_name | Mimir service name |

## Access

To access Grafana:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

Then navigate to http://localhost:3000 and login with:
- Username: admin
- Password: [configured in terraform.tfvars] 