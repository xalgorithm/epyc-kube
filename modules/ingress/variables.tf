variable "deploy_ingress" {
  description = "Whether to deploy Ingress resources"
  type        = bool
  default     = true
}

variable "grafana_domain" {
  description = "Domain name for Grafana"
  type        = string
  default     = "grafana.gray-beard.com"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "enable_tls" {
  description = "Whether to enable TLS for Ingress resources with Let's Encrypt"
  type        = bool
  default     = false
}

variable "cluster_issuer" {
  description = "Name of the ClusterIssuer for Let's Encrypt"
  type        = string
  default     = "letsencrypt-prod"
} 