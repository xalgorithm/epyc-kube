# Proxmox Module

This module handles the provisioning of Proxmox VMs for a Kubernetes cluster.

## Features

- Creates Proxmox VMs from a template
- Configures both public and private networking
- Sets up cloud-init for initial VM configuration
- Prepares VMs for K3s installation

## Usage

```hcl
module "proxmox" {
  source = "./modules/proxmox"

  proxmox_node     = "pve"
  vm_os_template   = 9000
  ssh_public_key   = "~/.ssh/id_ed25519.pub"
  public_bridge    = "vmbr1"
  private_bridge   = "vmbr2"
  public_gateway   = "10.0.1.209"
  
  vm_definitions = {
    "node1" = {
      cores       = 4
      memory      = 8192
      disk_size   = 128
      public_ip   = "10.0.1.211/24"
      private_ip  = "192.168.100.10/24"
      is_control  = true
    }
  }
  
  k3s_server_name = "node1"
  vm_user         = "ubuntu"
  k3s_token       = "your-secure-token"
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| proxmox_node | Proxmox node name | string | Yes |
| vm_os_template | VM template ID to clone | number | Yes |
| ssh_public_key | Path to SSH public key | string | Yes |
| public_bridge | Public network bridge name | string | Yes |
| private_bridge | Private network bridge name | string | Yes |
| public_gateway | Gateway IP for public network | string | Yes |
| vm_definitions | Map of VM definitions | map(object) | Yes |
| k3s_server_name | Name of the K3s server node | string | Yes |
| vm_user | Username for VM access | string | Yes |
| k3s_token | Token for K3s cluster | string | Yes |

## Outputs

| Name | Description |
|------|-------------|
| vm_ips | Map of VM names to their public IPs |
| control_node_name | Name of the control node VM |
| control_node_ip | Private IP of the control node |
| vm_names | List of VM names |
| k3s_master_ip | IP of the K3s master node |
| k3s_node_token | K3s node token (sensitive) | 