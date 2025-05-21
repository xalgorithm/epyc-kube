output "metallb_namespace" {
  description = "Namespace where MetalLB is deployed"
  value       = "metallb-system"
}

output "nfs_provisioner_namespace" {
  description = "Namespace where NFS provisioner is deployed"
  value       = "nfs-provisioner"
}

output "default_storage_class" {
  description = "Name of the default storage class"
  value       = "nfs-client"
} 