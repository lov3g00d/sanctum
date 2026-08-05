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
