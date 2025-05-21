variable "deploy_kubernetes" {
  description = "Whether to deploy Kubernetes resources"
  type        = bool
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "metallb_addresses" {
  description = "IP addresses range for MetalLB to use (can be a single IP with /32, a range, or a CIDR block)"
  type        = string
}

variable "nfs_server" {
  description = "IP address of the NFS server"
  type        = string
}

variable "nfs_path" {
  description = "NFS export path on the server"
  type        = string
}

variable "deploy_nfs_provisioner" {
  description = "Whether to deploy the NFS provisioner"
  type        = bool
  default     = false
} 