#!/usr/bin/env bash
# Break the availability SLI, watch the error budget burn, and wait for the
# multi-window burn-rate alert to fire. Then heal.
set -euo pipefail
NS=slo
PROM=http://localhost:19090

cfg() {
  kubectl -n "$NS" exec deploy/slo-app -- python -c \
    "import urllib.request; urllib.request.urlopen(urllib.request.Request('http://localhost:8080/config?error_rate=$1', method='POST')).read()"
}

echo "== inject 50% errors (burn rate should jump to ~50x) =="
cfg 0.5

echo "== watch burn rate + alert state =="
for i in $(seq 1 40); do
  burn=$(curl -s "$PROM/api/v1/query?query=slo:error_ratio:rate5m/0.01" | jq -r '.data.result[0].value[1] // "0"')
  state=$(curl -s "$PROM/api/v1/alerts" | jq -r '.data.alerts[] | select(.labels.alertname=="ErrorBudgetBurnFast") | .state' | head -1)
  printf "  +%3ds  burn(5m)=%.1fx  ErrorBudgetBurnFast=%s\n" "$((i * 10))" "$burn" "${state:-inactive}"
  [ "$state" = "firing" ] && { echo "  --> FIRING (page)"; break; }
  sleep 10
done

echo "== alert detail =="
curl -s "$PROM/api/v1/alerts" | jq -r '.data.alerts[] | select(.labels.alertname=="ErrorBudgetBurnFast") | "severity=\(.labels.severity)  summary=\(.annotations.summary)"'

echo "== heal (stop injecting errors) =="
cfg 0
echo "burn demo OK"
