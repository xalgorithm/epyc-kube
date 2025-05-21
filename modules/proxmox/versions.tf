terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.38.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
} 