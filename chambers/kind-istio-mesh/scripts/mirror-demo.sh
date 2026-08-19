#!/usr/bin/env bash
# Traffic mirroring (shadowing): send a copy of live traffic to v2 while users
# still get v1, so you can test the new version with real requests risk-free.
set -euo pipefail
NS=web
GW=http://localhost:18081

echo "== mirror 100% of traffic to v2 (primary stays v1) =="
kubectl -n "$NS" patch virtualservice web --type=json \
  -p='[{"op":"add","path":"/spec/http/0/mirror","value":{"host":"web.web.svc.cluster.local","subset":"v2"}},{"op":"add","path":"/spec/http/0/mirrorPercentage","value":{"value":100}}]'
sleep 2

echo "== send 10 requests to the gateway =="
for _ in $(seq 1 10); do curl -s -o /dev/null --max-time 5 "$GW/"; done
sleep 2
mirrored=$(kubectl -n "$NS" logs deploy/web-v2 -c web --since=8s 2>/dev/null | grep -c 'GET / HTTP' || true)
echo "  primary served v1; v2 saw $mirrored root requests in the last 8s (the shadowed copies)"
echo "== remove the mirror =="
kubectl -n "$NS" patch virtualservice web --type=json \
  -p='[{"op":"remove","path":"/spec/http/0/mirror"},{"op":"remove","path":"/spec/http/0/mirrorPercentage"}]'
echo "mirror demo OK"
