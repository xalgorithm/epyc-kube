variable "proxmox_node" {
  description = "The target Proxmox node name"
  type        = string
  default     = "pve" # Replace with your actual Proxmox node name if different
}

variable "proxmox_api_url" {
  description = "URL for the Proxmox API (e.g., https://proxmox.example.com:8006/api2/json)"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID (e.g., user@pam!tokenid)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "vm_os_template" {
  description = "ID of the template VM to clone"
  type        = number
}

variable "ssh_public_key" {
  description = "Path to the public SSH key file for accessing the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "public_bridge" {
  description = "Proxmox network bridge for the public network"
  type        = string
  default     = "vmbr1" # Adjust if your public bridge is different
}

variable "private_bridge" {
  description = "Proxmox network bridge for the private network"
  type        = string
  default     = "vmbr2" # Adjust if your private bridge is different
}

variable "public_gateway" {
  description = "Gateway IP for the public network"
  type        = string
  default     = "10.0.1.209"
}

variable "vm_definitions" {
  description = "Map defining the virtual machines"
  type = map(object({
    cores      = number
    memory     = number # In MiB
    disk_size  = number # In GB
    public_ip  = string # CIDR format e.g., "10.0.1.211/24"
    private_ip = string # CIDR format e.g., "192.168.100.10/24"
    is_control = bool   # Whether this is a control plane node
    public_gateway = string # Gateway IP for the VM's public network
  }))
  default = {
    "gimli" = {
      cores          = 4
      memory         = 8192
      disk_size      = 128
      public_ip      = "10.0.1.211/24"
      private_ip     = "192.168.100.10/24"
      is_control     = true
      public_gateway = "10.0.1.209"
    }
    "legolas" = {
      cores          = 4
      memory         = 8192
      disk_size      = 128
      public_ip      = "10.0.1.212/24"
      private_ip     = "192.168.100.11/24"
      is_control     = false
      public_gateway = "10.0.1.209"
    }
    "aragorn" = {
      cores          = 4
      memory         = 8192
      disk_size      = 128
      public_ip      = "10.0.1.213/24"
      private_ip     = "192.168.100.12/24"
      is_control     = false
      public_gateway = "10.0.1.209"
    }
  }
}

variable "k3s_server_name" {
  description = "Name of the VM that will serve as the k3s control plane"
  type        = string
  default     = "gimli"
}

variable "vm_user" {
  description = "Default username for the VMs created via cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "k3s_token" {
  description = "Secret token for k3s cluster registration"
  type        = string
  sensitive   = true
}

variable "deploy_kubernetes" {
  description = "Whether to deploy Kubernetes resources. Set to true only after cluster is ready and kubeconfig is configured."
  type        = bool
  default     = false
}

variable "nfs_server" {
  description = "IP address of the NFS server"
  type        = string
  default     = "10.0.1.210"
}

variable "nfs_path" {
  description = "NFS export path on the server"
  type        = string
  default     = "/data"
}

variable "metallb_addresses" {
  description = "IP address ranges for MetalLB to use (list of CIDRs or /32s)"
  type        = list(string)
  default     = ["10.0.1.214/32"]
}

variable "grafana_admin_password" {
  description = "Password for the Grafana admin user"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "deploy_nfs_provisioner" {
  description = "Whether to deploy the NFS provisioner. Set to true only if you have an NFS server available."
  type        = bool
  default     = true
}

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

variable "deploy_cert_manager" {
  description = "Whether to deploy cert-manager"
  type        = bool
  default     = true
}

variable "email_address" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
  default     = "admin@example.com"
}

variable "enable_tls" {
  description = "Whether to enable TLS for Ingress resources"
  type        = bool
  default     = false
}

variable "acme_staging" {
  description = "Whether to use Let's Encrypt staging server (for testing)"
  type        = bool
  default     = true
} 