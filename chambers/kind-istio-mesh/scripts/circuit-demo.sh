#!/usr/bin/env bash
# Circuit breaking: a tight connection pool sheds load with 503 instead of
# piling requests onto an overwhelmed backend.
set -euo pipefail
NS=web
GW=http://localhost:18081

echo "== tighten v1's connection pool (1 connection, 1 pending request) =="
kubectl -n "$NS" patch destinationrule web --type=json \
  -p='[{"op":"add","path":"/spec/trafficPolicy","value":{"connectionPool":{"tcp":{"maxConnections":1},"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1}}}}]'
sleep 2

echo "== fire 30 concurrent requests; the pool sheds the overflow =="
codes=$(seq 1 30 | xargs -P 30 -I{} curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 "$GW/")
echo "  200=$(echo "$codes" | grep -c '^200')   503=$(echo "$codes" | grep -c '^503')   (503 = circuit breaker shedding load)"

echo "== remove the limits =="
kubectl -n "$NS" patch destinationrule web --type=json -p='[{"op":"remove","path":"/spec/trafficPolicy"}]'
echo "circuit demo OK"
