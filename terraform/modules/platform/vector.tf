# Vector is the log collector. As an Agent it runs a DaemonSet, tails every
# container's stdout/stderr off the node via the kubernetes_logs source, and
# pushes to Loki. This is the metrics-logs-traces story's log leg: podinfo (and
# everything else) writes structured logs to stdout, Vector enriches each line
# with pod/namespace/container labels and forwards it to loki.monitoring:3100.
#
# The chart runs Helm `tpl` over customConfig, so Vector's own `{{ field }}`
# templates must be wrapped in `{{ "..." }}` to survive Helm rendering and reach
# Vector intact.
resource "helm_release" "vector" {
  count      = var.enable_vector ? 1 : 0
  name       = "vector"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name
  repository = "https://helm.vector.dev"
  chart      = "vector"
  version    = var.vector_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      role = "Agent"

      customConfig = {
        data_dir = "/vector-data-dir"
        api = {
          enabled = false
        }
        sources = {
          kubernetes_logs = {
            type = "kubernetes_logs"
          }
        }
        sinks = {
          loki = {
            type     = "loki"
            inputs   = ["kubernetes_logs"]
            endpoint = "http://loki.monitoring:3100"
            encoding = {
              codec = "json"
            }
            out_of_order_action = "accept"
            labels = {
              namespace = "{{ \"{{ kubernetes.pod_namespace }}\" }}"
              pod       = "{{ \"{{ kubernetes.pod_name }}\" }}"
              container = "{{ \"{{ kubernetes.container_name }}\" }}"
              node      = "{{ \"{{ kubernetes.pod_node_name }}\" }}"
            }
          }
        }
      }
    })
  ]
}
