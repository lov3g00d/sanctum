# The OpenTelemetry Collector is the trace ingestion point. Applications send OTLP
# to it rather than straight to Tempo so the wire protocol and the storage backend
# stay decoupled: the collector is where sampling, batching, attribute enrichment
# and fan-out to additional backends get added later without touching app config
# or Tempo. Running it as a Deployment (not a DaemonSet) suits pull-free OTLP push
# traffic from a handful of services.
#
# The pipeline is deliberately minimal: OTLP in, batch, OTLP out to Tempo. Batching
# is the one processor that always earns its place (it amortises export calls); the
# exporter is insecure OTLP because it is in-cluster traffic to tempo.monitoring:4317.
resource "helm_release" "otel_collector" {
  count      = var.enable_otel_collector ? 1 : 0
  name       = "opentelemetry-collector"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_collector_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      mode         = "deployment"
      replicaCount = 1

      image = {
        repository = "otel/opentelemetry-collector-contrib"
      }
      command = {
        name = "otelcol-contrib"
      }

      presets = {
        kubernetesAttributes = {
          enabled = true
        }
      }

      config = {
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
        processors = {
          batch = {}
        }
        exporters = {
          "otlp/tempo" = {
            endpoint = "tempo.monitoring:4317"
            tls = {
              insecure = true
            }
          }
        }
        service = {
          pipelines = {
            traces = {
              receivers  = ["otlp"]
              processors = ["batch"]
              exporters  = ["otlp/tempo"]
            }
          }
        }
      }
    })
  ]
}
