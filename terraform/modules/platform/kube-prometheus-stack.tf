# Prometheus, Alertmanager and Grafana. Values here are deliberately thin: the actual
# dashboards, recording rules and alert rules are version-controlled under the repo
# monitoring/ dir and delivered as ConfigMaps/PrometheusRules, not inlined in this chart.
resource "helm_release" "kube_prometheus_stack" {
  count      = var.enable_kube_prometheus_stack ? 1 : 0
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version

  atomic  = true
  wait    = true
  timeout = 600

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = "15d"

          # Discover ServiceMonitors/PodMonitors/PrometheusRules across all namespaces,
          # not just those carrying this release's Helm labels. Without this the chart
          # only scrapes its own objects and the repo's monitors are ignored.
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false

          resources = {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              memory = "2Gi"
            }
          }
        }
      }

      grafana = {
        enabled = true
      }
    })
  ]
}
