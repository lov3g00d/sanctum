# Chamber: slo-error-budget

An SLO practice lab on **kind + the Prometheus Operator**: a sample HTTP service
with tunable errors and latency, a load generator, and a prod-shaped Prometheus.
Define SLIs, an availability SLO with an error budget, and multi-window burn-rate
alerts, then break the service and watch the budget burn.

## Prod-shaped Prometheus

Runs **kube-prometheus-stack** (community Helm chart) configured like production,
not a toy:

- **HA Prometheus** (2 replicas) so a single pod loss does not blind you.
- **Persistent TSDB** (PVC) with a retention window.
- Real CPU/memory requests and limits.
- **ServiceMonitor**-based discovery of the app, and SLOs as a **PrometheusRule**
  custom resource with recording rules, all reconciled by the operator.

The cluster-infra scrapers (node-exporter, kube-state-metrics, kubelet) are off
to keep the focus on the app SLO; they would be on in a real cluster.

The two replicas are queried through one NodePort, so alert/query results can
flap as the round-robin hits a replica that is momentarily behind. That is the
point: HA Prometheus needs a dedup layer (Thanos Query, or Grafana pinned to one
replica) for a consistent view. This chamber leaves that as the next rung.

## Prerequisites

`nix develop` from the repo root (provides `kind`, `kubectl`, `helm`, `task`,
`jq`, `curl`) and a running Docker.

## Use

```sh
cd chambers/slo-error-budget
task up          # kind + kube-prometheus-stack + app + loadgen + rules
task status      # current availability SLI and burn rate
task break       # inject 50% errors
task heal        # stop injecting errors
task burn-demo   # break, wait for the burn-rate alert to fire, then heal
task down        # delete the kind cluster
```

Grafana: http://localhost:13000 (admin/admin). Prometheus: http://localhost:19090
(Alerts and Graph tabs). Both are exposed via NodePort through kind, no
port-forward needed.

## What it demonstrates

- SLIs as the ratio of good events to total (availability from non-5xx
  responses, latency from a histogram bucket), precomputed as recording rules.
- An availability SLO (99%) and its error budget (1%).
- Multi-window multi-burn-rate alerting: page only when both a short and a long
  window agree the budget is burning too fast, so brief blips do not page. The
  windows are lab-compressed for a fast demo; `k8s/slo-rules.yaml` notes the
  production values.
- The operator pattern: `ServiceMonitor` for scraping, `PrometheusRule` for
  SLOs, declarative HA Prometheus.
