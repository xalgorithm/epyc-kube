# Root Terraform configuration file
# This file serves as the entry point to the Terraform configuration

# Specify required providers
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.38.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
  required_version = ">= 1.0.0"
}

# Configure the Proxmox Provider
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true
  ssh {
    agent    = true
    username = var.vm_user
  }
}

# Configure Kubernetes Provider - conditional on kubeconfig existing
provider "kubernetes" {
  alias = "kubernetes_provider"

  # When deploy_kubernetes=false, create a stub configuration that doesn't connect to a real server
  host     = var.deploy_kubernetes ? "" : "https://10.0.1.211:6443"
  insecure = true

  # When deploy_kubernetes=true, use the actual kubeconfig
  config_path    = var.deploy_kubernetes ? local.kubeconfig_path : ""
  config_context = var.deploy_kubernetes ? "default" : ""
}

# Configure Helm Provider - conditional on kubeconfig existing
provider "helm" {
  alias = "helm_provider"

  kubernetes {
    # When deploy_kubernetes=false, create a stub configuration that doesn't connect to a real server
    host     = var.deploy_kubernetes ? "" : "https://10.0.1.211:6443"
    insecure = true

    # When deploy_kubernetes=true, use the actual kubeconfig
    config_path    = var.deploy_kubernetes ? local.kubeconfig_path : ""
    config_context = var.deploy_kubernetes ? "default" : ""
  }
}

# Define local variables
locals {
  kubeconfig_path = "${path.module}/kubeconfig.yaml"
}

# Create a placeholder kubeconfig file if it doesn't exist yet
resource "local_file" "placeholder_kubeconfig" {
  count    = fileexists(local.kubeconfig_path) ? 0 : 1
  filename = local.kubeconfig_path
  content  = <<-EOT
    # This is a placeholder kubeconfig file
    # Replace this with the actual kubeconfig after the k3s cluster is created
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        server: https://placeholder.k8s.local
        insecure-skip-tls-verify: true
      name: default
    contexts:
    - context:
        cluster: default
        user: default
      name: default
    current-context: default
    users:
    - name: default
      user:
        token: placeholder
  EOT
}

# Proxmox VM Module
module "proxmox" {
  source = "./modules/proxmox"

  # Provider configuration
  proxmox_node   = var.proxmox_node
  vm_os_template = var.vm_os_template
  ssh_public_key = var.ssh_public_key

  # Network configuration
  public_bridge  = var.public_bridge
  private_bridge = var.private_bridge
  public_gateway = var.public_gateway

  # VM configuration
  vm_definitions  = var.vm_definitions
  k3s_server_name = var.k3s_server_name
  vm_user         = var.vm_user
  k3s_token       = var.k3s_token
}

# Kubernetes Infrastructure Module - Only created if deploy_kubernetes is true
module "kubernetes" {
  source = "./modules/kubernetes"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.proxmox, local_file.placeholder_kubeconfig]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Configuration
  deploy_kubernetes = var.deploy_kubernetes
  kubeconfig_path   = local.kubeconfig_path

  # MetalLB configuration
  metallb_addresses = var.metallb_addresses

  # NFS configuration
  nfs_server             = var.nfs_server
  nfs_path               = var.nfs_path
  deploy_nfs_provisioner = var.deploy_nfs_provisioner
}

# Monitoring Stack Module - Only created if deploy_kubernetes is true
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Only deploy monitoring if kubernetes is deployed
  deploy_monitoring      = var.deploy_kubernetes
  kubeconfig_path        = local.kubeconfig_path
  grafana_admin_password = var.grafana_admin_password
}

# Ingress Module - Only created if deploy_kubernetes is true
module "ingress" {
  source = "./modules/ingress"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
  }

  # Configuration
  kubeconfig_path = local.kubeconfig_path
  grafana_domain  = var.grafana_domain
  deploy_ingress  = var.deploy_ingress
  enable_tls      = var.enable_tls
  cluster_issuer  = var.acme_staging ? "letsencrypt-staging" : "letsencrypt-prod"
}

# Cert-Manager Module for Let's Encrypt integration - Only created if deploy_kubernetes is true
module "cert_manager" {
  source = "./modules/cert-manager"
  count  = var.deploy_kubernetes ? 1 : 0

  depends_on = [module.kubernetes]

  # Use the aliased providers
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }

  # Configuration
  kubeconfig_path     = local.kubeconfig_path
  deploy_cert_manager = var.deploy_cert_manager
  email_address       = var.email_address
  staging             = var.acme_staging
}

# Generate SSH Config File
resource "local_file" "ssh_config" {
  content = templatefile("${path.module}/templates/ssh_config.tftpl", {
    vm_user        = var.vm_user
    vm_definitions = var.vm_definitions
    ssh_key_path   = pathexpand(var.ssh_public_key) != "" ? replace(pathexpand(var.ssh_public_key), ".pub", "") : "~/.ssh/id_ed25519"
    vm_ips         = module.proxmox.vm_ips
  })

  filename = "${path.module}/ssh_config"
}

# Note: Output declarations have been moved to outputs.tf 