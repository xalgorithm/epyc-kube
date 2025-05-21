terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
      configuration_aliases = [kubernetes]
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
      configuration_aliases = [helm]
    }
  }
} 