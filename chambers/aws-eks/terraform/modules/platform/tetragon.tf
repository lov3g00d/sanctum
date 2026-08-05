# Tetragon is the enforcement half of the runtime story, and complements Falco rather
# than replacing it. Falco watches syscalls in userspace and ALERTS after the fact;
# Tetragon runs the same observation in-kernel via eBPF and can act inline, sending a
# SIGKILL (or overriding a return value) before the operation completes. On this
# Cilium eBPF dataplane the probes are cheap, so detection (Falco) and prevention
# (Tetragon) are kept side by side: alert on everything, kill the unambiguous cases.
resource "helm_release" "tetragon" {
  count      = var.enable_tetragon ? 1 : 0
  name       = "tetragon"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "tetragon"
  version    = var.tetragon_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      tetragon = {
        # Richer exec/kprobe events: capabilities and namespaces on each process.
        enableProcessCred = true
        enableProcessNs   = true
        # Required for TracingPolicyNamespaced and pod-label scoping to take effect.
        # Chart-default true; pinned explicit because the enforcement policy below
        # relies on it to stay confined to the sanctum namespace.
        enablePolicyFilter = true
      }

      # Stream events to stdout so Vector picks them up into Loki alongside Falco.
      export = {
        mode = "stdout"
      }

      tetragonOperator = {
        tracingPolicy = {
          enabled = true
        }
      }
    })
  ]
}

# Enforcement example, scoped to the sanctum app namespace. TracingPolicyNamespaced
# only applies to pods in its own namespace, so a SIGKILL here can never reach a
# system pod in kube-system. It mirrors the sensitive paths the Falco rules detect
# (config/falco-rules.yaml) but acts instead of alerting: a write to the credential
# files or a read of the password hashes / kubelet client PKI kills the offending
# process in-kernel. security_file_permission's mask arg is MAY_EXEC=1, MAY_WRITE=2,
# MAY_READ=4.
resource "kubectl_manifest" "tetragon_enforce_sanctum" {
  # Also gated on cluster_posture: it owns the sanctum namespace this policy lands
  # in, so without it there is nothing to apply into.
  count = var.enable_tetragon && var.enable_cluster_posture ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cilium.io/v1alpha1"
    kind       = "TracingPolicyNamespaced"
    metadata = {
      name      = "sanctum-block-credential-access"
      namespace = "sanctum"
    }
    spec = {
      kprobes = [
        {
          call    = "security_file_permission"
          syscall = false
          args = [
            { index = 0, type = "file" },
            { index = 1, type = "int" },
          ]
          selectors = [
            {
              matchArgs = [
                { index = 0, operator = "Prefix", values = ["/etc/shadow", "/etc/sudoers", "/root/.ssh"] },
                { index = 1, operator = "Equal", values = ["2"] },
              ]
              matchActions = [{ action = "Sigkill" }]
            },
            {
              matchArgs = [
                { index = 0, operator = "Prefix", values = ["/etc/shadow", "/var/lib/kubelet/pki"] },
                { index = 1, operator = "Equal", values = ["4"] },
              ]
              matchActions = [{ action = "Sigkill" }]
            },
          ]
        },
      ]
    }
  })

  # The helm_release registers the CRDs; cluster_posture creates the sanctum namespace
  # this namespaced policy lands in. Without the latter edge the apply can race the
  # namespace and fail.
  depends_on = [helm_release.tetragon, kubectl_manifest.cluster_posture]
}
