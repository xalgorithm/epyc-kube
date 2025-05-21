# Kubernetes Infrastructure Module

# Deploy MetalLB using Helm
# Ref: https://metallb.universe.tf/installation/#installation-with-helm
resource "helm_release" "metallb" {
  count = var.deploy_kubernetes ? 1 : 0
  
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.13.7" # Use a compatible version
  namespace  = "metallb-system"

  create_namespace = true
  wait = true
  timeout = 600 # 10 minutes
}

# Deploy NFS Subdir External Provisioner using Helm
# Ref: https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
resource "helm_release" "nfs_provisioner" {
  count = var.deploy_kubernetes && var.deploy_nfs_provisioner ? 1 : 0
  
  name       = "nfs-subdir-external-provisioner"
  repository = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart      = "nfs-subdir-external-provisioner"
  namespace  = "nfs-provisioner"

  create_namespace = true

  set {
    name  = "nfs.server"
    value = var.nfs_server
  }

  set {
    name  = "nfs.path"
    value = var.nfs_path
  }

  set {
    name  = "storageClass.name"
    value = "nfs-client"
  }

  set {
    name  = "storageClass.defaultClass"
    value = "true"
  }
}

# MetalLB AddressPool for LoadBalancer Services
resource "local_file" "metallb_config" {
  count = var.deploy_kubernetes ? 1 : 0
  
  depends_on = [helm_release.metallb]
  
  content = <<-EOT
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: default-pool
      namespace: metallb-system
    spec:
      addresses:
      - ${var.metallb_addresses}
    ---
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: default-l2
      namespace: metallb-system
    spec:
      ipAddressPools:
      - default-pool
  EOT
  
  filename = "${path.module}/metallb-config.yaml"
}

resource "null_resource" "apply_metallb_config" {
  count = var.deploy_kubernetes ? 1 : 0
  
  depends_on = [
    helm_release.metallb,
    local_file.metallb_config
  ]

  provisioner "local-exec" {
    command = <<EOT
      # Wait for CRDs to be ready
      kubectl --kubeconfig=${var.kubeconfig_path} --insecure-skip-tls-verify wait --for=condition=established --timeout=120s crd/ipaddresspools.metallb.io
      kubectl --kubeconfig=${var.kubeconfig_path} --insecure-skip-tls-verify wait --for=condition=established --timeout=120s crd/l2advertisements.metallb.io
      
      # Apply the configuration
      kubectl --kubeconfig=${var.kubeconfig_path} --insecure-skip-tls-verify apply -f ${path.module}/metallb-config.yaml
    EOT
  }
} 