# Cloud/cluster posture scanners delivered as manifests: kube-bench (CIS EKS, an
# on-demand Job in kube-system that needs host access) and Prowler (CIS AWS, a
# weekly read-only CronJob using its IRSA ServiceAccount). Their ServiceAccounts,
# RBAC and the Prowler namespace ship in the same files and are kept intact.
# All are core resources, so no engine dependency.
data "kubectl_path_documents" "cspm" {
  pattern          = "${path.module}/policies/cspm/*.yaml"
  disable_template = true
}

resource "kubectl_manifest" "cspm" {
  for_each = var.enable_cspm ? data.kubectl_path_documents.cspm.manifests : {}

  yaml_body = each.value
}

# Prowler reads the whole account to score it against CIS, so it needs broad read-only
# access. The two AWS-managed policies (SecurityAudit for config/security metadata,
# ViewOnlyAccess for resource listings) cover that; the association binds them to the
# CronJob's service account via Pod Identity.
module "prowler_pod_identity" {
  count   = var.enable_cspm ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name            = "sanctum-prowler-cspm-${var.cluster_name}"
  use_name_prefix = false

  additional_policy_arns = {
    security_audit = "arn:aws:iam::aws:policy/SecurityAudit"
    view_only      = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
  }

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "security"
      service_account = "prowler"
    }
  }

  tags = local.common_tags
}
