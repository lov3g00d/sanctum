# Falco is the runtime-detection half of the DevSecOps story: it watches syscalls on
# every node and alerts on suspicious behaviour that admission control cannot catch (a
# shell in a container, unexpected outbound connections, writes to sensitive paths). The
# modern_ebpf driver avoids a kernel-module build and works on current EKS AMIs. Custom
# detection rules are maintained in the repo under security/falco and layered on top.
resource "helm_release" "falco" {
  count      = var.enable_falco ? 1 : 0
  name       = "falco"
  namespace  = kubernetes_namespace.falco[0].metadata[0].name
  repository = "https://falcosecurity.github.io/charts"
  chart      = "falco"
  version    = var.falco_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      driver = {
        kind = "modern_ebpf"
      }

      # Falcosidekick fans alerts out to the alerting stack; wiring the destination
      # (Alertmanager, Slack) is left to the environment config.
      falcosidekick = {
        enabled = true
      }

      collectors = {
        kubernetes = {
          enabled = true
        }
      }
    })
  ]
}
