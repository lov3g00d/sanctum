# Argo Rollouts is the progressive-delivery controller that reconciles the
# Rollout CRs the podinfo chart ships (canary steps, SLO-gated analysis). Argo CD
# hands the Rollout object to this controller; without it a Rollout manifest is
# inert. Kept as its own release, decoupled from Argo CD, so canary delivery can
# be toggled independently of the GitOps control plane.
resource "helm_release" "argo_rollouts" {
  count      = var.enable_argo_rollouts ? 1 : 0
  name       = "argo-rollouts"
  namespace  = kubernetes_namespace.argo_rollouts[0].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = var.argo_rollouts_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      controller = {
        replicas = 1
      }

      # The dashboard is an operator convenience, not part of the delivery path;
      # off by default to keep the footprint minimal.
      dashboard = {
        enabled = false
      }
    })
  ]
}
