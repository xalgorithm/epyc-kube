terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
      configuration_aliases = [kubernetes]
    }
  }
} 