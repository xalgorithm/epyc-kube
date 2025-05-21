variable "proxmox_node" {
  description = "The target Proxmox node name"
  type        = string
}

variable "vm_os_template" {
  description = "ID of the template VM to clone"
  type        = number
}

variable "ssh_public_key" {
  description = "Path to the public SSH key file for accessing the VMs"
  type        = string
}

variable "public_bridge" {
  description = "Proxmox network bridge for the public network"
  type        = string
}

variable "private_bridge" {
  description = "Proxmox network bridge for the private network"
  type        = string
}

variable "public_gateway" {
  description = "Gateway IP for the public network"
  type        = string
}

variable "vm_definitions" {
  description = "Map defining the virtual machines"
  type = map(object({
    cores       = number
    memory      = number
    disk_size   = number
    public_ip   = string
    private_ip  = string
    is_control  = bool
  }))
}

variable "k3s_server_name" {
  description = "Name of the VM that will serve as the k3s control plane"
  type        = string
}

variable "vm_user" {
  description = "Default username for the VMs created via cloud-init"
  type        = string
}

variable "k3s_token" {
  description = "Secret token for k3s cluster registration"
  type        = string
  sensitive   = true
} 