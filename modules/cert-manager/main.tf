resource "helm_release" "cert_manager" {
  count      = var.deploy_cert_manager ? 1 : 0
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true
  version    = "v1.14.4"  # Use the latest stable version

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "prometheus.enabled"
    value = "true"
  }
}

# Wait for the cert-manager webhook to be ready
resource "null_resource" "cert_manager_ready" {
  count      = var.deploy_cert_manager ? 1 : 0
  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=${var.kubeconfig_path}
      echo "Waiting for cert-manager webhook to be ready..."
      kubectl --insecure-skip-tls-verify -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=180s
    EOT
  }
}

# Create a local file for the ClusterIssuer manifest
resource "local_file" "cluster_issuer" {
  count      = var.deploy_cert_manager ? 1 : 0
  depends_on = [null_resource.cert_manager_ready]
  
  content    = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.staging ? "letsencrypt-staging" : "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = var.acme_server
        email  = var.email_address
        privateKeySecretRef = {
          name = var.staging ? "letsencrypt-staging" : "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "traefik"
              }
            }
          }
        ]
      }
    }
  })
  
  filename = "${path.module}/cluster-issuer.yaml"
}

# Apply the ClusterIssuer manifest
resource "null_resource" "apply_cluster_issuer" {
  count      = var.deploy_cert_manager ? 1 : 0
  depends_on = [local_file.cluster_issuer, null_resource.cert_manager_ready]
  
  # Wait a bit longer to ensure CRDs are properly registered
  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=${var.kubeconfig_path}
      # Wait for CRDs to be fully established
      echo "Waiting for cert-manager CRDs to be established..."
      sleep 30
      
      # Apply the ClusterIssuer
      echo "Applying ClusterIssuer..."
      kubectl --insecure-skip-tls-verify apply -f ${path.module}/cluster-issuer.yaml
    EOT
  }
} 