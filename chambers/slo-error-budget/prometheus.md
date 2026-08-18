# Prometheus, from the scrape up

How Prometheus actually works, at the level that separates people who install
`kube-prometheus-stack` from people who can debug why a target is `up` but has no
data, or why p99 latency reads 1s when it is really 3s. Grounded in this chamber
(the app metric `http_requests_total`, the SLI recording rules in
[`k8s/slo-rules.yaml`](k8s/slo-rules.yaml), and the burn-rate alert) and in
[`kind-kafka`](../kind-kafka/) (the same stack scraping Strimzi via a
`ServiceMonitor`). See also [observability](../../docs/observability.md) for how
this is delivered in the aws-eks platform.

## The one idea

Prometheus is a pull-based, dimensional time-series database that scrapes numeric
metrics over HTTP, stores them locally, and queries them with PromQL. Everything
else is detail around that sentence.

## The data model is the whole foundation

Every data point is a metric name plus a set of labels, mapping to a stream of
`(timestamp, float64)` samples:

```
http_requests_total{method="GET", path="/", status="500"}  ->  (ts, value)
```

- The metric name plus the exact label set uniquely identify a **time series**.
  `status="500"` and `status="200"` are two different series.
- A **sample** is one `(timestamp, value)`. A series is an ordered stream of them.
- The four metric types are a convention; the server stores everything as
  float64 series:
  - **Counter** only goes up (requests, errors). Never read raw, always `rate()`.
  - **Gauge** goes up and down (memory, queue depth).
  - **Histogram** bucketed observations: `_bucket{le="..."}` (cumulative),
    `_sum`, `_count`. This is how you get latency percentiles.
  - **Summary** client-side quantiles; avoid, they do not aggregate across
    instances.
- **Cardinality** = number of distinct series. This is the thing that kills
  Prometheus (see below).

## The exposition format is just text

A scrape of `/metrics` returns plain text, one sample per line:

```
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/",status="200"} 1955
http_request_duration_seconds_bucket{path="/",le="0.05"} 1801
http_request_duration_seconds_bucket{path="/",le="0.1"}  1950
http_request_duration_seconds_bucket{path="/",le="+Inf"} 1955
http_request_duration_seconds_sum{path="/"} 44.2
http_request_duration_seconds_count{path="/"} 1955
```

Specifics that bite:

- A counter never resets except on process restart. That reset is the only signal
  Prometheus has that the process restarted, and `rate()` special-cases it.
- Histogram buckets are cumulative: `le="0.1"` includes everything in `le="0.05"`.
  `le="+Inf"` equals `_count`. Quantiles are therefore interpolated, not exact.
- A labelled child does not appear in `/metrics` until first use. In the SLO
  chamber the `status="500"` series and the whole SLI stayed empty until the
  first injected error created it. Lazy child creation, not a bug.

## The components

- **Prometheus server** (one binary): retrieval/scraper, TSDB, PromQL engine,
  rules manager, HTTP API (`/api/v1/query`, `/query_range`, `/targets`,
  `/rules`, `/alerts`).
- **Service discovery**: static, or dynamic (Kubernetes, Consul, EC2, DNS). SD
  lists candidates; relabeling decides which to keep and how to label them.
- **Exporters**: translate non-Prometheus things into `/metrics`
  (`node_exporter`, `blackbox_exporter`, `kafka_exporter`, cAdvisor).
- **Client libraries**: in-app instrumentation. The SLO app uses
  `prometheus_client`.
- **Pushgateway**: the exception to pull, for short-lived batch jobs. Use
  sparingly; it breaks `up` semantics.
- **Alertmanager**: a separate binary. Prometheus evaluates alert rules and fires
  at Alertmanager, which decides what to do with them.

## The scrape lifecycle, precisely

Per target, every `scrape_interval` (default 60s):

1. `GET /metrics` with a hard `scrape_timeout` (must be <= interval).
2. Every sample in one scrape gets the same timestamp (the scrape start), so a
   target's series are aligned.
3. `sample_limit` / `target_limit` are enforced; a target over the cap fails the
   whole scrape (a cardinality circuit breaker).
4. Six meta-samples are synthesized: `up`, `scrape_duration_seconds`,
   `scrape_samples_scraped`, `scrape_samples_post_metric_relabeling`,
   `scrape_series_added`, `scrape_body_size_bytes`. `up==1` means the GET
   succeeded; a reachable-but-slow target is still `up==1` with high
   `scrape_duration_seconds`.
5. **Staleness**: when a series stops being exported or a target vanishes,
   Prometheus writes a stale marker (a NaN with a magic bit) at the next scrape,
   so graphs end instead of drawing a flat line forever. Deleted pods go stale in
   one scrape plus eval, not at retention time.

## Relabeling is a regex pipeline

SD emits candidates with `__meta_*` labels. `relabel_configs` transforms the
label set before scraping; `metric_relabel_configs` runs per sample after.

```yaml
- source_labels: [__meta_kubernetes_pod_label_app]
  regex: slo-app
  action: keep            # drop targets whose app label != slo-app
- source_labels: [__address__]
  regex: '([^:]+):.*'
  target_label: __address__
  replacement: '${1}:8080' # rewrite the scrape port
- action: labelmap
  regex: __meta_kubernetes_pod_label_(.+)  # promote pod labels to real labels
```

- `__address__` is the host:port scraped; `__metrics_path__` and `__scheme__` are
  also rewritable. Labels starting `__` are dropped after relabeling except
  `__name__`.
- `keep`/`drop` filter targets; `replace`/`labelmap`/`hashmod` rewrite labels.
  `hashmod` is how you shard: hash a label into N buckets, `keep` bucket i on
  shard i.
- `metric_relabel_configs drop` is your last line of defence against cardinality,
  dropping a noisy metric before it is stored.
- The Operator generates all of this from a `ServiceMonitor`.

## Storage on disk

```
wal/            write-ahead log, 128MB segments
chunks_head/    memory-mapped head chunks
01HX.../        an immutable persistent block (2h+ of data)
  chunks/       Gorilla-compressed sample chunks
  index         inverted index (postings lists) for this block
  tombstones    deletion markers
```

- Samples land in the in-memory **head** and are appended to the **WAL** for
  crash recovery. Every ~2h the head is cut into an immutable block.
- Chunks hold up to 120 samples, compressed with Gorilla (delta-of-delta on
  timestamps, XOR on values). Real cost is about **1.3 bytes per sample**: a
  15s-scraped series is ~7.5KB per day.
- **Compaction** merges adjacent blocks (2h -> 6h -> up to 10% of retention).
- **Retention** (`retention.time` or `retention.size`) drops whole blocks. You
  cannot keep one metric longer locally; retention is per-block, all or nothing.
- The **index** is inverted: for each `label=value` a postings list of series
  IDs. Queries intersect postings lists, which is why label selectors are fast
  and why high-cardinality labels bloat the index specifically.

## PromQL and its sharp edges

- **Instant vector**: one sample per series at eval time, meaning the most recent
  sample within the **lookback delta** (default 5m). A target down >5m returns
  nothing, not the stale value.
- **Range vector** (`[5m]`): a window per series; only valid as input to a
  function, cannot be plotted.
- **`rate(counter[5m])`** grabs samples in the window, corrects counter resets
  (any drop is treated as a restart and added back), computes
  `(last-first)/(dt)`, then extrapolates to the window edges. So `rate()` can read
  slightly higher than any real per-second value and can be fractional. The
  window must be **>= 4x the scrape interval** to be stable; the SLO chamber uses
  `[5m]` at a 15s scrape. `irate()` is last-two-samples (spiky); `increase()` is
  `rate() * window`.
- **`histogram_quantile(0.99, sum by (le) (rate(x_bucket[5m])))`** interpolates
  linearly inside the bucket the quantile lands in. Accuracy is entirely bounded
  by bucket boundaries: if the top finite bucket is `le="1"` and true p99 is 3s,
  it reports ~1s and you are blind. Bucket choice is the measurement. Native
  (exponential) histograms in Prometheus 2.40+/3.0 fix this with auto-scaling
  buckets and far less storage.
- `@` modifier and subqueries (`(...)[1h:1m]`) evaluate at a fixed time or over a
  rolling sub-window (e.g. max burn rate over the last hour).

## Rules and the alert state machine

- **Recording rules** run per group every group `interval`. Rules within a group
  run sequentially (so one can depend on a rule above it); groups run in parallel.
  Output is a normal series, computed once rather than per dashboard load. The SLO
  chamber precomputes `sli:availability:ratio_rate5m` and the per-window error
  ratios this way.
- **Alerting rule** state per matching series: expr true -> **pending**
  (`ALERTS{alertstate="pending"}`); true continuously for `for:` -> **firing**,
  pushed to Alertmanager on every eval; `keep_firing_for` holds firing briefly
  after it clears to stop flapping.
- The flap seen in the SLO chamber (pending -> inactive -> pending) was not the
  state machine: it was querying two independent HA replicas through one NodePort,
  each with its own eval clock and `ALERTS` series. That is the concrete reason HA
  Prometheus needs query-time dedup.

## Alertmanager

Prometheus only says "this is firing"; Alertmanager does the human-facing logic:

- **Grouping**: collapse many alerts from one outage into one notification.
- **Routing**: a tree sending alerts to receivers by label
  (`severity=page` -> pager, `severity=ticket` -> Jira).
- **Deduplication**: HA Prometheus pairs both fire the same alert; Alertmanager
  dedups by label set.
- **Inhibition**: suppress B while A fires (no "high latency" page when "cluster
  down" already paged).
- **Silences**: mute known or maintenance alerts for a window.

## Cardinality, with the cost model

A series is one unique `{__name__, labels...}` combo and costs roughly a few KB
of head RAM plus index entries, whether or not it is actively receiving samples,
until it goes stale and the block rotates. The killers:

- Unbounded label values: `user_id`, `request_id`, full URL, email, raw error
  strings. One `user_id` label on a busy endpoint is millions of series and an
  OOM.
- `le` and `quantile` are the only high-but-bounded labels you want.
- Combinations multiply: `path` (20) x `status` (5) x `method` (4) x `pod` (50) =
  20k series from one metric.

Controls: never put unbounded values in labels; `metric_relabel_configs drop` at
scrape; `sample_limit`; recording-rule then drop the raw high-cardinality series;
watch `prometheus_tsdb_head_series` and `scrape_series_added` and alert on your
own cardinality. Genuinely high-cardinality needs are a logs or traces job, not
metrics.

## Scaling past one box

- **HA**: two identical Prometheis, same scrape config; Alertmanager dedups
  identical alerts. Queries need dedup (Thanos Query, or pin Grafana to one).
- **Sharding**: N Prometheis, each scraping `hashmod(instance) == shard`. A global
  view then needs Thanos or federation.
- **Remote write**: Prometheus reads its own WAL and streams samples to an
  external store (Mimir, Cortex, Thanos Receive, VictoriaMetrics) via an
  auto-scaling queue of shards; if the remote is slow,
  `prometheus_remote_storage_samples_pending` climbs and it backpressures. Long
  retention, global query and horizontal scale while Prometheus stays a local
  collector.
- **Federation** (`/federate`): a global Prometheus scrapes aggregated series from
  leaves. Fine for a few top-level metrics, a trap for raw series (you just moved
  the cardinality).
- **Thanos sidecar**: uploads the immutable 2h blocks to object storage; Thanos
  Store and Query fan out across all sidecars plus the bucket for unlimited
  retention and one global query endpoint.

## The Operator (why kube-prometheus-stack matters)

On Kubernetes you do not hand-edit `prometheus.yml`. The Prometheus Operator turns
CRDs into running config: `Prometheus` (server: replicas, retention, resources,
storage), `ServiceMonitor`/`PodMonitor` (what to scrape, by label selector),
`PrometheusRule` (recording and alerting rules), `Alertmanager` and
`AlertmanagerConfig` (routing). You declare intent; the operator renders
`prometheus.yml`, reloads, and reconciles. Both the SLO and Kafka chambers use it.

## The one-paragraph version

Prometheus scrapes text metrics on a fixed interval, timestamps a whole scrape
together, and stores samples in a Gorilla-compressed local TSDB (~1.3 B/sample)
fronted by an inverted index; PromQL reads the most-recent-within-5m sample for
instant queries and extrapolated counter rates over windows; recording rules
pre-aggregate, alerting rules run a pending->firing state machine into
Alertmanager; the whole thing lives and dies by cardinality (a few KB of head
memory per unique label set); and you scale past one box with HA plus dedup,
hashmod sharding, or remote-write to Mimir/Thanos. Everything else is relabeling
and YAML.
