module "external_dns_pod_identity" {
  count   = var.enable_external_dns ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name            = "external-dns-${var.cluster_name}"
  use_name_prefix = false

  attach_external_dns_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }

  tags = local.common_tags
}

resource "helm_release" "external_dns" {
  count      = var.enable_external_dns ? 1 : 0
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      provider = {
        name = "aws"
      }

      serviceAccount = {
        create = true
        name   = "external-dns"
      }

      # txt registry with a per-cluster owner id keeps two clusters from fighting over
      # the same records if they ever share a hosted zone.
      policy     = "sync"
      registry   = "txt"
      txtOwnerId = var.cluster_name
    })
  ]
}
