#!/usr/bin/env bash
# Elasticsearch cluster health and a breakdown of the parsed app logs by level,
# read through the Elasticsearch REST API.
set -euo pipefail

CTX=kind-elk
NS=elk

PW=$(kubectl --context "$CTX" -n "$NS" get secret elk-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d)
es() { kubectl --context "$CTX" -n "$NS" exec elk-es-default-0 -- curl -sk -u "elastic:$PW" "$@" 2>/dev/null; }

echo "=== cluster health ==="
es https://localhost:9200/_cluster/health | python3 -c 'import sys,json
d=json.load(sys.stdin)
print("status: %s   nodes: %s" % (d["status"], d["number_of_nodes"]))'

echo "=== logstash-app: total docs and breakdown by parsed level ==="
es -H 'Content-Type: application/json' 'https://localhost:9200/logstash-app-*/_search?size=0' \
  -d '{"aggs":{"by_level":{"terms":{"field":"level.keyword"}}}}' \
  | python3 -c 'import sys,json
d=json.load(sys.stdin)
print("total: %s" % d.get("hits",{}).get("total",{}).get("value",0))
for b in d.get("aggregations",{}).get("by_level",{}).get("buckets",[]):
    print("  %-6s %s" % (b["key"], b["doc_count"]))'
