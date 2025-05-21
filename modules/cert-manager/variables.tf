variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "deploy_cert_manager" {
  description = "Whether to deploy cert-manager"
  type        = bool
  default     = true
}

variable "email_address" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
}

variable "acme_server" {
  description = "ACME server URL for Let's Encrypt"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "staging" {
  description = "Whether to use Let's Encrypt staging server (for testing)"
  type        = bool
  default     = false
} 