module "alb_controller_irsa" {
  count   = var.enable_alb_controller ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.1"

  name                                   = "alb-controller-${var.cluster_name}"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    this = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

resource "helm_release" "alb_controller" {
  count      = var.enable_alb_controller ? 1 : 0
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.region
      vpcId       = var.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.alb_controller_irsa[0].arn
        }
      }

      replicaCount = 2

      resources = {
        requests = {
          cpu    = "100m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }
    })
  ]
}
