# Tempo is the traces backend, the third pillar. The OTel Collector forwards
# spans here over OTLP and Grafana reads them through the Tempo datasource, where
# a trace can pivot to the matching Loki logs and Prometheus metrics.
#
# Single-binary Tempo with the local (filesystem) trace backend keeps the
# reference cheap; production points storage.trace at S3 and leaves everything
# else the same. OTLP grpc/http receivers are enabled explicitly because that is
# the single ingest path the collector uses. The query/metrics HTTP API stays on
# the chart default 3200, which is the port the Grafana datasource targets.
resource "helm_release" "tempo" {
  count      = var.enable_tempo ? 1 : 0
  name       = "tempo"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      tempo = {
        storage = {
          trace = {
            backend = "local"
            local = {
              path = "/var/tempo/traces"
            }
            wal = {
              path = "/var/tempo/wal"
            }
          }
        }
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
        }
      }

      persistence = {
        enabled = false
      }

      serviceMonitor = {
        enabled = true
      }
    })
  ]
}
