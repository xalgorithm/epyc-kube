# Proxmox VM Creation Module

# Local variables for the module
locals {
  # Extract just the IP address from CIDR notation for easier use
  node_ips = { for k, v in var.vm_definitions : k => {
    public_ip  = split("/", v.public_ip)[0]
    private_ip = split("/", v.private_ip)[0]
  }}

  # Assuming 'gimli' is the first server node to initialize the cluster
  first_node_name = "gimli"
  k3s_server_url  = "https://${local.node_ips[local.first_node_name].private_ip}:6443"

  # Assuming network interfaces are named eth0 (public) and eth1 (private) by cloud-init order
  private_nic = "eth1"

  # Parse the SSH key file content
  ssh_public_key_content = file(var.ssh_public_key)
}

# VM Resources
resource "proxmox_virtual_environment_vm" "k8s_node" {
  for_each = var.vm_definitions

  node_name    = var.proxmox_node
  name         = each.key
  description  = "Kubernetes node ${each.key} managed by Terraform"
  tags         = ["k8s", "terraform"]
  
  # VM Hardware Configuration
  cpu {
    cores = each.value.cores
    type  = "host"
  }
  
  memory {
    dedicated = each.value.memory
  }
  
  # OS Boot Configuration
  clone {
    vm_id = var.vm_os_template
    full  = true
  }
  
  agent {
    enabled = true
  }
  
  # Boot order configuration
  boot_order = ["scsi0", "network0"]
  
  # Cloud-Init Configuration 
  initialization {
    user_account {
      username = var.vm_user
      password = "temporary-password" # Consider using Vault or other secret management
      keys     = [local.ssh_public_key_content]
    }
    
    ip_config {
      ipv4 {
        address = each.value.public_ip
        gateway = try(each.value.public_gateway, var.public_gateway)
      }
    }
    
    ip_config {
      ipv4 {
        address = each.value.private_ip
      }
    }
  }

  # Network Interfaces
  network_device {
    bridge = var.public_bridge
  }
  
  network_device {
    bridge = var.private_bridge
  }
  
  # Disk Configuration
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
    file_format  = "raw"
  }
  
  # Serial device for Ubuntu
  serial_device {}
  
  # Start the VM on creation
  on_boot = true
  
  lifecycle {
    ignore_changes = [
      initialization,
      tags
    ]
  }
}

# Make sure the snippets directory exists
resource "null_resource" "create_snippet_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/snippets"
  }
}

# Local file resources to generate user-data files for Cloud-Init
resource "local_file" "cloud_init_user_data" {
  for_each = var.vm_definitions
  
  depends_on = [null_resource.create_snippet_dir]
  
  content = templatefile("${path.root}/templates/cloud-init-userdata.tftpl", {
    hostname      = each.key
    vm_user       = var.vm_user
    ssh_key       = chomp(local.ssh_public_key_content)
    is_control    = each.value.is_control
    k3s_token     = var.k3s_token
    api_server_ip = split("/", var.vm_definitions[var.k3s_server_name].private_ip)[0]
  })
  
  filename = "${path.module}/snippets/user-data-${each.key}.yml"
} 