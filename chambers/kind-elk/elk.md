# The Elastic Stack, end to end

How the log pipeline in this chamber works, from `helm`-free ECK install to a
grok-parsed error landing in Elasticsearch. Grounded in the `loggen` app, the
Logstash grok filter, and the Filebeat DaemonSet under `k8s/`.

## The one idea

Logs are the third pillar of observability, next to metrics (Prometheus, the
`kind-slo-error-budget` chamber) and active checks (Icinga, `kind-icinga`). The
Elastic Stack is a pipeline that turns raw log lines into searchable, structured
data: **ship** them off each node (Filebeat), **parse** the unstructured text
into fields (Logstash), **store and search** them (Elasticsearch), and **explore**
them (Kibana). The whole point is to go from "a wall of text" to "show me every
`status:500` in the last hour", and the step that makes that possible is parsing.

```
loggen (stdout)  ->  Filebeat  ->  Logstash (grok)  ->  Elasticsearch  ->  Kibana
   text lines        ship          parse to fields      store + search     explore
```

## ECK: the operator model

Elastic on Kubernetes is run with the **ECK operator** (Elastic Cloud on
Kubernetes). It is the recommended path now that the community Helm charts were
archived. You install two things (`crds.yaml` and `operator.yaml`), then declare
each component as a CRD: `Elasticsearch`, `Kibana`, `Logstash`, `Beat`. The
operator reconciles them into StatefulSets/Deployments/DaemonSets and, crucially,
handles the things that are tedious by hand:

- **TLS**: it generates a CA and per-component certificates.
- **Credentials**: it creates the `elastic` superuser (password in the
  `elk-es-elastic-user` secret) and a dedicated, least-privilege user per
  association.
- **Associations**: a `Kibana` or `Logstash` with an `elasticsearchRef` gets the
  ES host, a generated user, the password, and the CA injected as env vars (for
  Logstash: `ELK_ES_HOSTS`, `ELK_ES_USER`, `ELK_ES_PASSWORD`,
  `ELK_ES_SSL_CERTIFICATE_AUTHORITY`), which the pipeline references.

## The components

- **Elasticsearch** - the store and search engine. A distributed document
  database with an inverted index. Single-node here (`node.roles` all-in-one).
- **Kibana** - the UI. Data views, Discover (search), dashboards, and Dev Tools.
  Reads Elasticsearch over the association.
- **Logstash** - the parse/transform stage. Runs a pipeline of
  `input -> filter -> output`. Here: a `beats` input on 5044, a `grok` filter,
  and an `elasticsearch` output.
- **Filebeat** - the shipper. A DaemonSet on every node that tails container log
  files (`/var/log/containers/*.log`), enriches each line with Kubernetes
  metadata, and forwards to Logstash.

## A log line, end to end

`task logs-demo` walks this path:

1. `loggen` prints a line to stdout: `ERROR 500 GET /healthz 340ms internal server error`.
   The container runtime writes it to `/var/log/containers/loggen-*.log`.
2. **Filebeat** (DaemonSet) harvests the file, wraps the line in an event with
   `kubernetes.*` metadata, and ships it to Logstash over plain TCP 5044.
3. **Logstash** receives it on the `beats` input. The `grok` filter matches the
   line against a pattern and extracts fields: `level=ERROR`, `status=500` (int),
   `method`, `req_path`, `latency_ms` (int), `log_message`.
4. The `elasticsearch` output writes the structured document to an index, over
   TLS, authenticated as the association's user.
5. **Kibana** (or the `_search` API) queries it: `status:500` returns the parsed
   error docs, aggregatable by `level`, `req_path`, etc.

## Grok: the "L" in ELK

Grok is pattern-matching for logs: named regex building blocks compose into a
pattern that carves an unstructured line into fields.

```
%{WORD:level} %{NUMBER:status:int} %{WORD:method} %{DATA:req_path} %{NUMBER:latency_ms:int}ms %{GREEDYDATA:log_message}
```

The `:int` type hints matter: they make `status` and `latency_ms` numbers in
Elasticsearch, so you can range-query and aggregate them (average latency, count
by status). A line the pattern cannot match is tagged `_grokparsefailure` and
still stored, so you can find and fix parse gaps. Emitting JSON would sidestep all
of this with a `json` filter, which is why this chamber deliberately emits text:
grok on text is the teachable skill.

## Two hops, two security models

- **Filebeat -> Logstash** is NOT an ECK-managed association. You configure
  `output.logstash` by hand pointing at the Logstash beats service
  (`elk-ls-beats:5044`), and keep it plain TCP. Trying to TLS this hop is a cert
  rabbit hole for a lab.
- **Logstash -> Elasticsearch** IS an ECK association (`elasticsearchRefs`). ECK
  injects the host, user, password, and CA; the pipeline references them.

**The least-privilege gotcha:** the association user ECK mints for Logstash has a
restricted role that can only write to `logstash-*` (and `ecs-logstash-*`)
indices. Point the output at `app-logs-*` and every write fails with a 403
`security_exception` (`action [indices:admin/auto_create] is unauthorized`). The
fix is either to name the index under the allowed pattern (this chamber writes to
`logstash-app-*`) or to grant the user a custom role. It is a good reminder that
ECK does not hand out a superuser to every component.

## Indices, data streams, and health

- The output writes a **time-based index** (`logstash-app-YYYY.MM.dd`). Because
  the config sets an explicit `index`, Logstash uses a classic index, not a data
  stream; data streams are the newer default for append-only logs.
- A single-node Elasticsearch leaves indices **YELLOW** when a default template
  requests a replica shard that has no second node to land on. Yellow is healthy
  for one node; only worry about **RED** (unassigned primaries). This chamber
  happens to report GREEN because the log index template requests zero replicas.
- Elasticsearch needs the host `vm.max_map_count >= 262144` (it memory-maps index
  files). Most Linux hosts already satisfy this; if not, raise it with `sysctl`.

## How it contrasts with metrics and checks

- **Prometheus** answers "how much / how fast" from numeric time series; great for
  rates, latencies, and SLOs, useless for "what did request X actually do".
- **Icinga** answers "is this up" with discrete states and notifications.
- **ELK** answers "what happened, in detail" by making the raw event text
  searchable. You reach for it when a metric spikes and you need the specific log
  lines behind it. The three are complementary, not substitutes.

## The install this chamber runs

`task up` builds the cluster, installs the ECK operator and waits for it, then
brings the stack up in dependency order: Elasticsearch and Kibana first (wait for
health), then Logstash (wait for the pipeline), then Filebeat and the app. All
four components are pinned to one Elastic Stack version; the ECK operator version
is separate. `task logs-demo` breaks the app and finds the parsed errors in
Elasticsearch by field query.

## The one-paragraph version

ECK is an operator that runs the Elastic Stack from CRDs, generating TLS and
per-component credentials and wiring associations between them. Filebeat tails
container logs on every node and ships them over plain TCP to Logstash, whose grok
filter parses each unstructured line into typed fields and writes them, over an
ECK-managed TLS association, into a `logstash-*` index in Elasticsearch, where
Kibana and the `_search` API can query and aggregate them. It is the searchable
raw-event pillar of observability, the detail you reach for when a metric spikes.
