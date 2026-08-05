# Kyverno is the admission-control half of the DevSecOps story: it validates, mutates and
# generates resources at deploy time (block latest tags, require resource limits, enforce
# signed images). The policies themselves are version-controlled under kubernetes/security
# and security/kyverno; this release only installs the engine.
resource "helm_release" "kyverno" {
  count      = var.enable_kyverno ? 1 : 0
  name       = "kyverno"
  namespace  = kubernetes_namespace.kyverno[0].metadata[0].name
  repository = "https://kyverno.github.io/kyverno"
  chart      = "kyverno"
  version    = var.kyverno_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      # Multiple admission-controller replicas so a single node loss does not drop the
      # webhook and stall every deploy in the cluster.
      admissionController = {
        replicas = 3
      }

      backgroundController = {
        replicas = 2
      }

      cleanupController = {
        replicas = 2
      }

      reportsController = {
        replicas = 2
      }
    })
  ]
}
