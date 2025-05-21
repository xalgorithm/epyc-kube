# Kubernetes Module

This module handles the deployment of core Kubernetes infrastructure components.

## Features

- Deploys MetalLB for LoadBalancer service support
- Sets up NFS storage provisioner for persistent volumes
- Configures network infrastructure

## Usage

```hcl
module "kubernetes" {
  source = "./modules/kubernetes"
  count  = var.deploy_kubernetes ? 1 : 0
  
  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }
  
  deploy_kubernetes = true
  kubeconfig_path   = "${path.module}/kubeconfig.yaml"
  metallb_addresses = "10.0.1.214/32"
  nfs_server        = "10.0.1.210"
  nfs_path          = "/data"
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| deploy_kubernetes | Whether to deploy Kubernetes resources | bool | Yes |
| kubeconfig_path | Path to the kubeconfig file | string | Yes |
| metallb_addresses | IP addresses for MetalLB | string | Yes |
| nfs_server | NFS server IP address | string | Yes |
| nfs_path | NFS export path | string | Yes |

## Outputs

| Name | Description |
|------|-------------|
| metallb_namespace | MetalLB namespace |
| nfs_provisioner_namespace | NFS provisioner namespace |
| default_storage_class | Default storage class name | 