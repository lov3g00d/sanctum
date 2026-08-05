# Karpenter's controller role, node role, instance profile and spot-interruption SQS
# queue come from the upstream EKS submodule, pinned to the same version as the eks
# module so the two stay in lockstep. v21 wires the controller via EKS Pod Identity
# rather than IRSA, so this path needs the eks-pod-identity-agent addon on the cluster.
#
# The EC2NodeClass and NodePool custom resources are day-2 Kubernetes tuning and are not
# delivered by this module. This module only provisions the AWS-side identity and the
# controller install.
module "karpenter" {
  count   = var.enable_karpenter ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.24.1"

  cluster_name = var.cluster_name

  namespace       = "kube-system"
  service_account = "karpenter"

  create_pod_identity_association = true
  enable_spot_termination         = true

  tags = local.common_tags
}

resource "helm_release" "karpenter" {
  count     = var.enable_karpenter ? 1 : 0
  name      = "karpenter"
  namespace = "kube-system"
  chart     = "oci://public.ecr.aws/karpenter/karpenter"
  version   = var.karpenter_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "karpenter"
      }

      settings = {
        clusterName       = var.cluster_name
        interruptionQueue = module.karpenter[0].queue_name
      }

      replicas = 2

      controller = {
        resources = {
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    })
  ]
}
