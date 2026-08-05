module "external_dns_irsa" {
  count   = var.enable_external_dns ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.1"

  name                       = "external-dns-${var.cluster_name}"
  attach_external_dns_policy = true

  oidc_providers = {
    this = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
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
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_irsa[0].arn
        }
      }

      # txt registry with a per-cluster owner id keeps two clusters from fighting over
      # the same records if they ever share a hosted zone.
      policy     = "sync"
      registry   = "txt"
      txtOwnerId = var.cluster_name
    })
  ]
}
