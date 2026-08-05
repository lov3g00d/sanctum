# The managed node group below is the baseline capacity that keeps the cluster
# reachable (CoreDNS, the AWS load balancer controller, Karpenter itself). Day-to-day
# workload scaling is meant to run on Karpenter: it provisions right-sized nodes from
# pending pods in seconds and consolidates them when idle, which is cheaper and faster
# than a fixed ASG per instance type. Karpenter's NodePool/EC2NodeClass are Kubernetes
# resources, so they live in kubernetes/, not here. This module only exposes the OIDC
# provider and node security group Karpenter needs.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.1"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  endpoint_public_access       = var.endpoint_public_access
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.public_access_cidrs

  enabled_log_types = var.enabled_log_types

  # KMS envelope encryption of Kubernetes secrets at rest. The module creates and
  # rotates a dedicated CMK; without this, secrets are only encrypted with the
  # EKS-managed key.
  encryption_config = {
    resources = ["secrets"]
  }

  enable_irsa = true

  # Karpenter (and other platform addons) authenticate via EKS Pod Identity, which
  # requires this agent running on the cluster. Without it the pod-identity
  # associations created in modules/platform never resolve credentials.
  addons = {
    eks-pod-identity-agent = {}
  }

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    for arn in var.admin_access_entries : md5(arn) => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      subnet_ids     = var.private_subnet_ids
    }
  }

  tags = var.tags
}
