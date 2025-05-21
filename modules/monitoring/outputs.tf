output "monitoring_namespace" {
  description = "Namespace where monitoring components are deployed"
  value       = "monitoring"
}

output "grafana_service_name" {
  description = "Name of the Grafana service"
  value       = "kube-prometheus-stack-grafana"
}

output "prometheus_service_name" {
  description = "Name of the Prometheus service"
  value       = "kube-prometheus-stack-prometheus"
}

output "loki_gateway_service" {
  description = "Name of the Loki gateway service"
  value       = "loki-gateway"
}

output "tempo_service_name" {
  description = "Name of the Tempo service"
  value       = "tempo"
}

output "mimir_service_name" {
  description = "Name of the Mimir service"
  value       = "mimir-nginx"
} 