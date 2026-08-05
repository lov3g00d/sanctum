# Prometheus, Alertmanager and Grafana. The chart installs the engine; the cluster-wide
# config it runs on is owned here and delivered through the chart values: global alert
# rules, Alertmanager routing, and the Loki/Tempo Grafana datasources. Each is kept as a
# reviewable file under config/ and loaded with file()/yamldecode rather than inlined.
# podinfo's own recording rules, dashboards and ServiceMonitor still ship with the app in
# charts/podinfo; the Grafana sidecar picks up its dashboard ConfigMaps.
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

      # Global Kube/Node/RDS/platform alert rules. The file is already {groups: [...]};
      # additionalPrometheusRulesMap keys each entry by name and renders a PrometheusRule,
      # so there is no CRD-ordering concern (the chart owns the CRD and the object).
      additionalPrometheusRulesMap = {
        "nimbus-global" = yamldecode(file("${path.module}/config/prometheus-rules.yaml"))
      }

      alertmanager = {
        # Routing (page -> PagerDuty, ticket -> Slack) and inhibitions. Secret values
        # (Slack webhook, PagerDuty key) are placeholders injected from a Secret at
        # deploy time, never committed.
        config = yamldecode(file("${path.module}/config/alertmanager.yaml"))
      }

      grafana = {
        enabled = true

        # Prometheus is auto-provisioned by the chart (uid "prometheus"); only Loki and
        # Tempo are added here, which is why the source file drops the Prometheus entry.
        additionalDataSources = yamldecode(file("${path.module}/config/grafana-datasources.yaml")).datasources

        sidecar = {
          dashboards = {
            # podinfo delivers its RED/SLO dashboards as ConfigMaps labelled
            # grafana_dashboard="1"; keep the sidecar on and searching all namespaces
            # so those load even though they live with the app, not this release.
            enabled         = true
            searchNamespace = "ALL"
          }
        }
      }
    })
  ]
}
