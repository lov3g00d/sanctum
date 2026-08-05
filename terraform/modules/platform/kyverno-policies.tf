# Kyverno ClusterPolicies delivered as manifests: supply-chain (verify cosign
# signatures Enforce, require SBOM attestation Audit) and the pod-hardening set
# (no :latest, run-as-non-root, read-only rootfs, resource limits, drop-all-caps).
# Kept as reviewable YAML under policies/kyverno.
#
# These are custom resources of the Kyverno CRDs, so they depend_on the engine's
# helm_release having installed those CRDs first; without it the apply races the
# CRD registration and fails.
data "kubectl_path_documents" "kyverno_policies" {
  pattern = "${path.module}/policies/kyverno/*.yaml"

  # The policies carry Kyverno JMESPath ({{ ... }}); disable the provider's own
  # ${...} templating so it never touches the manifest bodies.
  disable_template = true
}

resource "kubectl_manifest" "kyverno_policies" {
  for_each = var.enable_kyverno && var.enable_kyverno_policies ? data.kubectl_path_documents.kyverno_policies.manifests : {}

  yaml_body = each.value

  depends_on = [helm_release.kyverno]
}
