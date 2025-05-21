# VM Outputs
output "vm_ips" {
  description = "A map of VM names to their public IP addresses"
  value       = module.proxmox.vm_ips
}

output "k3s_master_ip" {
  description = "The IP address of the Kubernetes master node"
  value       = module.proxmox.k3s_master_ip
}

output "k3s_node_token" {
  description = "The node token for joining workers to the K3s cluster"
  value       = module.proxmox.k3s_node_token
  sensitive   = true
}

output "ssh_config_path" {
  description = "Path to the generated SSH config file"
  value       = "${path.module}/ssh_config"
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = local.kubeconfig_path
}

# User Information for accessing services
output "access_instructions" {
  description = "Instructions for accessing the cluster"
  sensitive   = true
  value       = <<EOT
----- Kubernetes Cluster Access -----

1. SSH to the control node:
   $ ssh -F ssh_config ${module.proxmox.control_node_name}

2. Set up kubectl:
   $ export KUBECONFIG=${local.kubeconfig_path}

3. Access Grafana:
   a. Via Port Forwarding (Local Development):
      $ kubectl --insecure-skip-tls-verify port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
      Then open: http://localhost:3000
   
   b. Via Domain (Production Access):
      Open: https://${var.grafana_domain}
      
      Note: TLS is ${var.enable_tls ? "enabled" : "disabled"} for this domain.
      ${var.enable_tls && var.acme_staging ? "Using Let's Encrypt staging environment - certificate will show as invalid but encryption works." : ""}
   
   Username: admin
   Password: ${var.grafana_admin_password} (specified in terraform.tfvars)
EOT
} 