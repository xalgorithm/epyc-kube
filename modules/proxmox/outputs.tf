output "vm_ips" {
  description = "Map of VM names to their IP addresses"
  value       = { for name, vm in proxmox_virtual_environment_vm.k8s_node : name => local.node_ips[name].public_ip }
}

output "control_node_name" {
  description = "Name of the control node VM"
  value       = var.k3s_server_name
}

output "control_node_ip" {
  description = "Private IP of the control node"
  value       = local.node_ips[var.k3s_server_name].private_ip
}

output "vm_names" {
  description = "List of VM names created"
  value       = keys(proxmox_virtual_environment_vm.k8s_node)
}

output "k3s_master_ip" {
  description = "IP address of the Kubernetes master node"
  value       = local.node_ips[var.k3s_server_name].private_ip
}

output "k3s_node_token" {
  description = "The node token for joining workers to the K3s cluster"
  value       = var.k3s_token
  sensitive   = true
} 