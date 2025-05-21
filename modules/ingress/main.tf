resource "kubernetes_manifest" "grafana_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "grafana-ingress"
      namespace = "monitoring"
      annotations = var.enable_tls ? {
        "cert-manager.io/cluster-issuer" = var.cluster_issuer
        "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
        "traefik.ingress.kubernetes.io/router.tls" = "true"
      } : {}
    }
    spec = {
      ingressClassName = "traefik"
      tls = var.enable_tls ? [
        {
          hosts      = [var.grafana_domain]
          secretName = "grafana-tls"
        }
      ] : null
      rules = [
        {
          host = var.grafana_domain
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "kube-prometheus-stack-grafana"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
} 