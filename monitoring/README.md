# Monitoring and observability

Observability for Nimbus: how we know the platform is healthy, how we find out
first when it is not, and how we decide whether a problem is worth waking someone
for. The config in this directory is written as plain Prometheus, Alertmanager
and Grafana files so the intent is reviewable in one place. In production it is
deployed as [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts)
via Helm/ArgoCD, where the Prometheus Operator renders the same scrape jobs from
`ServiceMonitor`/`PodMonitor` objects and the same rules from `PrometheusRule`
objects. Everything runs in the `monitoring` namespace.

## The four golden signals

Every service is judged on the same four signals, so an on-call engineer knows
what to look at before they know anything about the service:

| Signal | What it answers | Where it comes from |
|--------|-----------------|---------------------|
| Latency | How long requests take (and slow vs fast) | `http_request_duration_seconds` histogram |
| Traffic | How much demand there is | `http_requests_total` rate |
| Errors | What share of requests fail | `http_requests_total{status_code=~"5.."}` ratio |
| Saturation | How close to a resource limit | node CPU/memory/disk, RDS connections/CPU |

## RED for the service, USE for the resources

The golden signals split cleanly by what you are looking at.

**RED** (Rate, Errors, Duration) fits the request-driven core, `nimbus-orders-api`.
It is exactly latency + traffic + errors, framed per endpoint. The dashboard
`grafana/dashboards/orders-api-red.json` is nothing but RED, sliced by route.

**USE** (Utilization, Saturation, Errors) fits the resources underneath: nodes,
RDS, Redis. For a node you ask how busy it is (utilization), whether work is
queuing (saturation, e.g. `DiskPressure`/`MemoryPressure` conditions), and
whether it is throwing hardware/kubelet errors. `node-exporter` and
`kube-state-metrics` supply the series; the `nodes.alerts` and `rds.alerts`
groups act on them.

The two are complementary, not competing: RED tells you the service is hurting,
USE tells you which resource to blame.

## Metrics, logs, traces

Three signals, three backends, one correlation story:

- **Metrics (Prometheus).** Cheap, numeric, aggregatable. The basis for
  dashboards and alerts. Answers "is it broken and how badly", not "why".
- **Logs (Loki).** High-cardinality detail per event. Answers "what exactly
  happened to this request". Queried with LogQL, provisioned as a Grafana
  datasource alongside Prometheus.
- **Traces (Tempo, via OpenTelemetry).** The path of one request across
  services. Answers "where did the time go" and "which hop failed". The app
  emits OTel spans; exemplars on the latency histogram and a `trace_id` in log
  lines let you jump metric -> log -> trace without leaving Grafana.

Reach for metrics first (is there a problem, how big), logs to characterise it,
traces to localise it.

## SLOs and error budgets

We set a Service Level Objective, `nimbus-orders-api` availability >= **99.9%**
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

- `OrdersAPIErrorBudgetBurnFast` (the SLO is burning fast)
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
before the budget is gone. Thresholds live in
`prometheus/rules/alerts.yml`, the SLI series in `recording.rules.yml`.

## Layout

```
prometheus/prometheus.yml            scrape jobs, external labels, rule + AM wiring
prometheus/rules/recording.rules.yml RED + SLI series (level:metric:operation)
prometheus/rules/alerts.yml          burn-rate, symptom, Kube/Node/RDS, platform
alertmanager/alertmanager.yml        routing (page->PagerDuty, ticket->Slack), inhibitions
grafana/provisioning/datasources.yml Prometheus + Loki
grafana/provisioning/dashboards.yml  file-provider for the dashboards below
grafana/dashboards/orders-api-red.json  RED, per route
grafana/dashboards/slo.json             SLI, error budget, burn rate
```

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
