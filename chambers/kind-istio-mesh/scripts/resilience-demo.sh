#!/usr/bin/env bash
# Timeouts and retries: the mesh caps how long a call can take and retries
# transient failures, giving reliability the app never implemented.
set -euo pipefail
NS=web
GW=http://localhost:18081

setcfg() { # query string, e.g. latency_ms=3000
  kubectl -n "$NS" exec deploy/web-v1 -c web -- python -c \
    "import urllib.request; urllib.request.urlopen(urllib.request.Request('http://localhost:8080/config?$1', method='POST')).read()" >/dev/null
}

count200() { # n
  local ok=0
  for _ in $(seq 1 "$1"); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$GW/")" = 200 ]; then ok=$((ok + 1)); fi
  done
  echo "$ok"
}

echo "### TIMEOUT ###"
echo "== make v1 take 3s, set a 1s route timeout =="
setcfg "latency_ms=3000"
kubectl -n "$NS" patch virtualservice web --type=json -p='[{"op":"add","path":"/spec/http/0/timeout","value":"1s"}]'
sleep 2
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$GW/")
echo "  request returned HTTP $code (504 = Istio cut it at 1s instead of waiting 3s)"
kubectl -n "$NS" patch virtualservice web --type=json -p='[{"op":"remove","path":"/spec/http/0/timeout"}]'
setcfg "latency_ms=0"

echo "### RETRIES ###"
echo "== make v1 fail 50% of the time =="
setcfg "error_rate=0.5"
echo "  without retries: $(count200 40) / 40 succeeded"
echo "== add 3 retries on 5xx =="
kubectl -n "$NS" patch virtualservice web --type=json \
  -p='[{"op":"add","path":"/spec/http/0/retries","value":{"attempts":3,"perTryTimeout":"1s","retryOn":"5xx"}}]'
sleep 2
echo "  with retries:    $(count200 40) / 40 succeeded  (the mesh retried the transient 503s)"
kubectl -n "$NS" patch virtualservice web --type=json -p='[{"op":"remove","path":"/spec/http/0/retries"}]'
setcfg "error_rate=0"
echo "resilience demo OK"
