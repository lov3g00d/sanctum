#!/usr/bin/env bash
# Break the app so it emits ERROR / HTTP 500 log lines, then show those logs
# arriving in Elasticsearch parsed into fields by the Logstash grok filter.
# Proves the whole path: app stdout -> Filebeat -> Logstash -> Elasticsearch.
set -euo pipefail

CTX=kind-elk
NS=elk

PW=$(kubectl --context "$CTX" -n "$NS" get secret elk-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d)
es() { kubectl --context "$CTX" -n "$NS" exec elk-es-default-0 -- curl -sk -u "elastic:$PW" "$@" 2>/dev/null; }
app_health() {
  kubectl --context "$CTX" -n "$NS" exec deploy/loggen -- python -c \
    "import urllib.request,json,sys; urllib.request.urlopen(urllib.request.Request('http://localhost:8080/config',data=json.dumps({'healthy':sys.argv[1]=='true'}).encode(),headers={'Content-Type':'application/json'},method='POST'))" "$1"
}
count_500() {
  es -H 'Content-Type: application/json' 'https://localhost:9200/logstash-app-*/_search?size=0' \
    -d '{"query":{"term":{"status":500}}}' \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("hits",{}).get("total",{}).get("value",0))'
}

echo "== baseline: 500-status docs already in Elasticsearch =="
before=$(count_500)
echo "  status:500 docs = $before"

echo "== break: app now emits ERROR / HTTP 500 lines =="
app_health false

echo "== wait for the parsed 500 docs to land in Elasticsearch =="
after=$before
for _ in $(seq 1 30); do
  after=$(count_500)
  [ "$after" -gt "$before" ] && break
  sleep 5
done
echo "  status:500 docs: $before -> $after"

echo "== a sample parsed doc (fields extracted by the Logstash grok filter) =="
es -H 'Content-Type: application/json' 'https://localhost:9200/logstash-app-*/_search?size=1' \
  -d '{"query":{"term":{"status":500}},"sort":[{"@timestamp":{"order":"desc"}}]}' \
  | python3 -c 'import sys,json
s=json.load(sys.stdin)["hits"]["hits"]
if not s:
    print("  (no parsed 500 docs yet)"); raise SystemExit(0)
d=s[0]["_source"]
for k in ("level","status","method","req_path","latency_ms","log_message","message"):
    if k in d: print("  %-12s %s" % (k, d[k]))'

echo "== heal: back to INFO / HTTP 200 =="
app_health true
echo "logs-demo OK"
