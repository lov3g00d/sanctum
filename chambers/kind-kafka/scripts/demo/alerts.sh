#!/usr/bin/env bash
# Fire an alert on purpose: kill a broker so partitions go under-replicated,
# watch UnderReplicatedPartitions go Pending then Firing in Prometheus, then let
# the broker rejoin and watch it resolve. Relies on the 15s scrape interval so
# the short outage is captured before the broker recovers.
set -euo pipefail
NS=kafka
MON=monitoring

kubectl -n "$MON" port-forward svc/monitoring-kube-prometheus-prometheus 19090:9090 >/tmp/pf-alerts.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null' EXIT
sleep 5
A="http://localhost:19090/api/v1/alerts"
state() { curl -s "$A" 2>/dev/null | jq -r '.data.alerts[] | select(.labels.alertname=="UnderReplicatedPartitions") | .state' | head -1; }

VICTIM=$(kubectl -n "$NS" get pod -l strimzi.io/broker-role=true -o jsonpath='{.items[0].metadata.name}')
echo "== KILL $VICTIM =="
kubectl -n "$NS" delete pod "$VICTIM" --wait=false

echo "== watch the alert fire =="
for i in $(seq 1 18); do
  st=$(state)
  echo "  +$((i*10))s  alert=${st:-inactive}"
  [ "$st" = "firing" ] && { echo "  --> FIRING"; break; }
  sleep 10
done
curl -s "$A" 2>/dev/null | jq -r '.data.alerts[] | select(.labels.alertname=="UnderReplicatedPartitions") | "  severity=\(.labels.severity)  summary=\(.annotations.summary)"'

echo "== watch it resolve as the broker rejoins =="
for i in $(seq 1 18); do
  st=$(state)
  echo "  +$((i*10))s  alert=${st:-inactive}"
  [ -z "$st" ] && { echo "  --> resolved"; break; }
  sleep 10
done
echo "alerts demo OK"
