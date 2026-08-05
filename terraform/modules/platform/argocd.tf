# Argo CD runs single-replica here (HA off) because this is the dev-scale install; a
# prod overlay can flip the redis-ha/controller replica counts via the chart values.
# The Application/ApplicationSet CRs that define what Argo CD deploys live in gitops/,
# so this release only stands up the control plane.
resource "helm_release" "argocd" {
  count      = var.enable_argocd ? 1 : 0
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd[0].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      redis-ha = {
        enabled = false
      }

      controller = {
        replicas = 1
      }

      server = {
        replicas = 1
      }

      repoServer = {
        replicas = 1
      }

      applicationSet = {
        replicas = 1
      }
    })
  ]
}
