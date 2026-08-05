# The managed node group below is the baseline capacity that keeps the cluster
# reachable (CoreDNS, the AWS load balancer controller, Karpenter itself). Day-to-day
# workload scaling is meant to run on Karpenter: it provisions right-sized nodes from
# pending pods in seconds and consolidates them when idle, which is cheaper and faster
# than a fixed ASG per instance type. Karpenter's NodePool/EC2NodeClass are Kubernetes
# resources delivered as day-2 tuning, not here. This module only exposes the OIDC
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

  # Cilium is the dataplane and replaces kube-proxy (modules/platform/cilium.tf), so
  # this cluster is deliberately kube-proxy-free. The v21 module hardcodes
  # bootstrap_self_managed_addons = false, meaning EKS installs no networking addon
  # unless it is declared here. kube-proxy is therefore absent simply because it is
  # not listed. vpc-cni stays because ENI-mode Cilium still relies on it for ENI/IP
  # allocation (its dataplane is patched off at day-0, see docs/networking-cilium.md);
  # coredns and the pod-identity agent are the remaining cluster essentials.
  addons = {
    eks-pod-identity-agent = {}
    coredns                = {}
    vpc-cni                = {}
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

      # Cilium taints each node with node.cilium.io/agent-not-ready until its agent
      # is Ready. Seeding the same taint at the node group keeps every workload off a
      # node until Cilium owns its dataplane, which avoids pods coming up with broken
      # networking during bootstrap on a kube-proxy-free cluster. Cilium removes it.
      taints = {
        cilium_not_ready = {
          key    = "node.cilium.io/agent-not-ready"
          value  = "true"
          effect = "NO_EXECUTE"
        }
      }
    }
  }

  tags = var.tags
}
