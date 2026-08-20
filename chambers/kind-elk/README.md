# Chamber: kind-elk

The Elastic Stack (ELK) on kind: a log generator whose lines are shipped by
Filebeat, parsed by a Logstash grok filter into fields, stored in Elasticsearch,
and explored in Kibana. Break the app and find the parsed `status:500` errors by
query. The logs pillar to sit beside the metrics (`kind-slo-error-budget`) and
active-check (`kind-icinga`) chambers.

## Stack

kind + the **ECK operator** (Elastic Cloud on Kubernetes), the recommended way to
run Elastic on Kubernetes now that the community Helm charts are archived. ECK
deploys and wires the components through CRDs and handles TLS and the generated
`elastic` password automatically. A Flask app emits one semi-structured **text**
log line per second (`LEVEL STATUS METHOD PATH LATENCYms MESSAGE`), deliberately
not JSON so the Logstash `grok` filter has to parse it.

```
loggen (stdout)  ->  Filebeat  ->  Logstash (grok)  ->  Elasticsearch  ->  Kibana
   text lines        ship          parse to fields      store + search     explore
```

Filebeat ships to Logstash over plain TCP (5044); Logstash writes to
Elasticsearch over the ECK-managed association (injected host, user, password,
and CA). Everything is pinned to one Elastic Stack version.

## Prerequisites

`nix develop` from the repo root (provides `kind`, `kubectl`, `helm`, `task`,
`python`) and a running Docker. The host needs `vm.max_map_count >= 262144`
(Elasticsearch bootstrap check); most Linux hosts already satisfy this
(`sysctl vm.max_map_count`).

## Use

```sh
cd chambers/kind-elk
task up          # kind + ECK + Elasticsearch, Kibana, Logstash, Filebeat + app
task creds       # print the Kibana URL and the elastic password
task status      # cluster health and the log doc count by parsed level
task logs-demo   # break the app, then find the parsed ERROR/500 logs in ES
task break       # emit ERROR / HTTP 500 log lines
task heal        # back to INFO / HTTP 200
task down        # delete the kind cluster
```

Kibana: http://localhost:15601 (elastic / the password from `task creds`). In
Kibana, create a data view on `logstash-app-*` and use Discover to search the parsed
fields (`level`, `status`, `req_path`, `latency_ms`).

## What it demonstrates

- **The three-tier log pipeline**: ship (Filebeat), parse (Logstash), store and
  search (Elasticsearch), explore (Kibana). The classic ELK-B flow.
- **Grok parsing**: turning an unstructured text line into typed fields
  (`status` and `latency_ms` as integers), which is what makes the logs queryable
  and aggregatable. This is the teachable "L" in ELK.
- **The ECK operator model**: Elasticsearch, Kibana, Logstash, and Beats as CRDs,
  with automatic TLS and credential wiring between them.
- **Break and find**: flip the app to errors and locate them in Elasticsearch by
  a field query (`status:500`), the everyday incident-debugging loop.

## Reference

[`elk.md`](elk.md) is a deep-dive on how the stack works end to end (the ECK
operator, each component's job, the ship/parse/store/explore pipeline, grok, the
associations and security model, indices vs data streams, and how it contrasts
with metrics-based observability), grounded in this chamber.
[`elk-architecture.html`](elk-architecture.html) is a self-contained visual
reference to the same material (open it in a browser).
