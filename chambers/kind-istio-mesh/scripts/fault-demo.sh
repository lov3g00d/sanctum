#!/usr/bin/env bash
# Fault injection: Istio returns errors for a percentage of requests without the
# app being involved at all, so you can test how callers handle failures.
set -euo pipefail
NS=web
GW=http://localhost:18081

echo "== inject a 40% HTTP 500 abort fault on the route =="
kubectl -n "$NS" patch virtualservice web --type=json \
  -p='[{"op":"add","path":"/spec/http/0/fault","value":{"abort":{"percentage":{"value":40},"httpStatus":500}}}]'
sleep 2

ok=0
err=0
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$GW/")
  if [ "$code" = 200 ]; then ok=$((ok + 1)); else err=$((err + 1)); fi
done
echo "  of 30 requests: 200=$ok  aborted=$err  (Istio injected the errors; the app was never called)"

echo "== remove the fault =="
kubectl -n "$NS" patch virtualservice web --type=json -p='[{"op":"remove","path":"/spec/http/0/fault"}]'
echo "fault demo OK"
