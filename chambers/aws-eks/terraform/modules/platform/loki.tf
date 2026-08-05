# Loki is the logs backend, the second pillar next to Prometheus metrics. Vector
# ships container logs here and Grafana queries them with LogQL through the Loki
# datasource.
#
# SingleBinary (monolithic) mode with filesystem storage is chosen deliberately:
# it runs the whole read/write/backend path in one process on a local PVC, which
# is the cheapest, least-moving-parts option for a reference cluster. Production
# swaps this for the distributed (read/write/backend) deployment backed by S3, at
# which point the schemaConfig and object store below become the only things that
# change. The gateway and memcached tiers are turned off here because a single
# binary has nothing to fan out to; `loki.monitoring:3100` is the one endpoint
# both Vector and Grafana talk to.
resource "helm_release" "loki" {
  count      = var.enable_loki ? 1 : 0
  name       = "loki"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version

  atomic  = true
  wait    = true
  timeout = 600

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        storage = {
          type = "filesystem"
        }
        schemaConfig = {
          configs = [
            {
              from         = "2024-04-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "loki_index_"
                period = "24h"
              }
            },
          ]
        }
      }

      singleBinary = {
        replicas = 1
      }

      read    = { replicas = 0 }
      write   = { replicas = 0 }
      backend = { replicas = 0 }

      gateway      = { enabled = false }
      chunksCache  = { enabled = false }
      resultsCache = { enabled = false }
      lokiCanary   = { enabled = false }
      test         = { enabled = false }
    })
  ]
}
