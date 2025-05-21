variable "deploy_monitoring" {
  description = "Whether to deploy the monitoring stack"
  type        = bool
}

variable "monitoring_namespace" {
  description = "Namespace to deploy monitoring resources into"
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_password" {
  description = "Password for the Grafana admin user"
  type        = string
  sensitive   = true
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
} 