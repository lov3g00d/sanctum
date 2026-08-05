# Monitoring and observability

Observability for Nimbus: how we know the platform is healthy, how we find out
first when it is not, and how we decide whether a problem is worth waking someone
for. The config is written as plain Prometheus, Alertmanager and Grafana files
under [`terraform/modules/platform/config/`](../terraform/modules/platform/config)
so the intent is reviewable in one place. In production it is delivered by the
Terraform platform module as
[`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts)
(Helm), where the Prometheus Operator renders the same scrape jobs from
`ServiceMonitor`/`PodMonitor` objects and the same rules from `PrometheusRule`
objects. The global alert rules, Alertmanager routing and the Loki/Tempo Grafana
datasources are folded into the chart values from those files. Everything runs in
the `monitoring` namespace.

## The four golden signals

Every service is judged on the same four signals, so an on-call engineer knows
what to look at before they know anything about the service:

| Signal | What it answers | Where it comes from |
|--------|-----------------|---------------------|
| Latency | How long requests take (and slow vs fast) | `http_request_duration_seconds` histogram |
| Traffic | How much demand there is | `http_requests_total` rate |
| Errors | What share of requests fail | `http_requests_total{status=~"5.."}` ratio |
| Saturation | How close to a resource limit | node CPU/memory/disk, RDS connections/CPU |

## RED for the service, USE for the resources

The golden signals split cleanly by what you are looking at.

**RED** (Rate, Errors, Duration) fits the request-driven core, `podinfo`.
It is exactly latency + traffic + errors, framed per endpoint. podinfo's RED
dashboard ships with the app in [`charts/podinfo`](../charts/podinfo) (delivered
as a Grafana-sidecar ConfigMap) and is nothing but RED, sliced by path. Because
podinfo's request counter carries no path label, the per-path RED series come
from the `http_request_duration_seconds` histogram `_count`.

**USE** (Utilization, Saturation, Errors) fits the resources underneath: nodes,
RDS, Redis. For a node you ask how busy it is (utilization), whether work is
queuing (saturation, e.g. `DiskPressure`/`MemoryPressure` conditions), and
whether it is throwing hardware/kubelet errors. `node-exporter` and
`kube-state-metrics` supply the series; the `nodes.alerts` and `rds.alerts`
groups act on them.

The two are complementary, not competing: RED tells you the service is hurting,
USE tells you which resource to blame.

## Metrics, logs, traces, flows

Four signals, one correlation story, all surfaced in Grafana:

- **Metrics (Prometheus).** Cheap, numeric, aggregatable. The basis for
  dashboards and alerts. Answers "is it broken and how badly", not "why".
  Delivered by the kube-prometheus-stack.
- **Logs (Vector -> Loki).** High-cardinality detail per event. Answers "what
  exactly happened to this request". Vector runs as a node agent (DaemonSet),
  tails every container's stdout, labels each line with pod/namespace/container,
  and ships it to Loki. Queried with LogQL through the Loki datasource.
- **Traces (podinfo -> OTel Collector -> Tempo).** The path of one request
  across services. Answers "where did the time go" and "which hop failed".
  podinfo emits OTLP spans to the OpenTelemetry Collector, which batches and
  forwards them to Tempo. Sending through the collector rather than straight to
  Tempo keeps sampling, enrichment and backend choice out of the app.
- **Flows (Hubble).** Network-level visibility from the Cilium dataplane: which
  pod talked to which, on what port, allowed or dropped. Answers questions the
  other three cannot, such as "is a NetworkPolicy silently dropping this call".
  Hubble metrics land in Prometheus and the flow graph in the Hubble UI.

The three application signals are stitched together in Grafana. The Tempo
datasource carries `tracesToLogsV2` (to Loki) and `tracesToMetrics` (to
Prometheus) links, so a slow span pivots straight to that pod's logs and its RED
metrics without a manual query. Reach for metrics first (is there a problem, how
big), logs to characterise it, traces to localise it, flows when the problem is
in the network path rather than the app.

Turning on tracing in podinfo (`PODINFO_OTEL_SERVICE_NAME`) also enables its OTLP
log exporter, but that path is incidental. The authoritative log path is stdout
-> Vector -> Loki, which captures every container uniformly rather than only the
ones instrumented for OTel.

## SLOs and error budgets

We set a Service Level Objective, `podinfo` availability >= **99.9%**
over a rolling 30 days, and measure it with an SLI: the ratio of successful
(non-5xx) requests to total requests. 4xx is the caller's fault and does not
count against us.

99.9% leaves a **0.1% error budget**: roughly 43 minutes of full outage per 30
days, or an equivalent smear of partial failure. The budget reframes reliability
as a resource you spend, not a state you defend. Budget left means we can ship;
budget gone means reliability work takes priority over features. It also sets the
alert thresholds below, so paging is tied to real objective risk rather than a
round number someone liked.

## Alert on symptoms, not causes

The rule that keeps the pager useful: **page on what the user feels, ticket the
rest.** A customer does not care that a node went NotReady if Karpenter replaced
it before any request failed. They care when requests start failing or slowing.

So the only things that page are user-visible symptoms:

- `PodinfoErrorBudgetBurnFast` (the SLO is burning fast)
- `HighErrorRate` (a blunt backstop for a hard outage)

Everything a customer does not feel yet is a **ticket** to investigate in hours,
routed to Slack: crash loops, replica mismatches, node pressure, RDS headroom,
expiring certs. They are causes worth fixing before they become symptoms, but not
worth the 3am escalation.

### Multi-window, multi-burn-rate

Rather than "alert when errors > X%", we alert on how fast the error budget is
burning, using the [Google SRE workbook](https://sre.google/workbook/alerting-on-slos/)
pattern. Burn rate is the multiple of budget-consumption relative to steady
state; at 1x the budget lasts exactly the 30 days.

| Path | Long window | Short window | Burn rate | Budget spent | Severity |
|------|-------------|--------------|-----------|--------------|----------|
| Fast | 1h | 5m | 14.4x | ~2% in 1h | page |
| Slow | 6h | 30m | 6x | ~5% in 6h | ticket |

Two windows per alert on purpose: the **long** window gives significance (a real
sustained burn, not a blip), the **short** window gives fast reset (the alert
clears quickly once the burn stops). Two burn rates give sensitivity without
noise: a fast catastrophic burn pages immediately, a slow grind opens a ticket
before the budget is gone. podinfo's burn-rate and symptom thresholds and its
SLI recording rules ship with the app (`charts/podinfo`, as a `PrometheusRule`);
what remains in `config/prometheus-rules.yaml` is the global Kube/Node/RDS/platform
set.

## Layout

```
terraform/modules/platform/config/
  prometheus-rules.yaml       global Kube/Node/RDS/platform alerts
  alertmanager.yaml           routing (page->PagerDuty, ticket->Slack), inhibitions
  grafana-datasources.yaml    Loki + Tempo (with trace correlation); Prometheus
                              is auto-provisioned by the chart with uid "prometheus"
```

podinfo's own observability wiring, its RED + SLO dashboards, its RED/SLI
recording rules, its burn-rate and symptom alerts, and the ServiceMonitor that
replaces the static `podinfo` scrape job, ships with the app under
[`charts/podinfo`](../charts/podinfo). The Prometheus Operator (kube-prometheus-stack)
selects those `ServiceMonitor`/`PrometheusRule` objects, and the Grafana sidecar
picks up the dashboard ConfigMaps from the `monitoring` namespace.

## Assumptions

- Metrics for AWS-managed stores (RDS, Redis) come from the
  [`cloudwatch_exporter`](https://github.com/prometheus/cloudwatch_exporter)
  (`aws_rds_<metric>_<statistic>` naming). It and `cert-manager` are discovered
  through the annotation-based `kubernetes-pods` scrape job, not dedicated jobs.
- `CertificateExpiringSoon` watches in-cluster `cert-manager` certificates.
  Public edge TLS terminates at Cloudflare and is monitored there.
- Kubernetes and node alert expressions are the
  [kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin)
  canonical forms, with `KubePod*` joined to `kube_pod_info` so they carry a
  `node` label for the NodeNotReady inhibition.
