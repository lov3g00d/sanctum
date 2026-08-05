# IRSA role for cert-manager to solve ACME DNS01 challenges via Route53. The built-in
# policy grants the change/list actions cert-manager needs; hosted-zone scoping is left
# to the default (all zones) since the module contract does not carry a zone id.
module "cert_manager_irsa" {
  count   = var.enable_cert_manager ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.1"

  name                       = "cert-manager-${var.cluster_name}"
  attach_cert_manager_policy = true

  oidc_providers = {
    this = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }

  tags = local.common_tags
}

resource "helm_release" "cert_manager" {
  count      = var.enable_cert_manager ? 1 : 0
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager[0].metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      # cert-manager ships its CRDs in the chart but does not install them unless asked.
      # Installing them here keeps the CRDs and the controller on the same release so an
      # upgrade moves both together, instead of tracking CRDs out of band.
      crds = {
        enabled = true
      }

      serviceAccount = {
        create = true
        name   = "cert-manager"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.cert_manager_irsa[0].arn
        }
      }
    })
  ]
}
