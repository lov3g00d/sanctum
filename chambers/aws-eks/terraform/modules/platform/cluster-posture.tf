# App-namespace posture for sanctum, delivered as manifests: the PSA-restricted
# namespace, default-deny + DNS-baseline NetworkPolicies, least-privilege RBAC, and
# the compute ResourceQuota and LimitRange. The platform owns the sanctum namespace;
# the ArgoCD ApplicationSet syncs the workload into it (its CreateNamespace option is
# then a no-op against an existing namespace). All core resources, no engine dependency.
data "kubectl_path_documents" "cluster_posture" {
  pattern          = "${path.module}/policies/cluster/*.yaml"
  disable_template = true
}

resource "kubectl_manifest" "cluster_posture" {
  for_each = var.enable_cluster_posture ? data.kubectl_path_documents.cluster_posture.manifests : {}

  yaml_body = each.value
}
