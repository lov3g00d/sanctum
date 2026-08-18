#!/usr/bin/env bash
# Show how a consumer group spreads a topic's partitions across its members, and
# rebalances live when a member leaves (authenticated as admin).
#   ./groups-demo.sh [group]
set -euo pipefail
NS=kafka
GROUP="${1:-app}"

POD=$(kubectl -n "$NS" get pod -l strimzi.io/cluster=sanctum,strimzi.io/broker-role=true \
  -o jsonpath='{.items[0].metadata.name}')
PW=$(kubectl -n "$NS" get secret admin -o jsonpath='{.data.password}' | base64 -d)

kubectl -n "$NS" exec -i "$POD" -- bash -c 'cat > /tmp/admin.props' <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="$PW";
EOF
CG=/opt/kafka/bin/kafka-consumer-groups.sh
CFG="--command-config /tmp/admin.props"

members() {
  kubectl -n "$NS" exec "$POD" -- $CG --bootstrap-server localhost:9092 \
    --describe --group "$GROUP" --members --verbose $CFG
}

echo "== scale the consumer to 3 members =="
kubectl -n "$NS" scale deploy/consumer --replicas=3
kubectl -n "$NS" rollout status deploy/consumer --timeout=120s
sleep 15

echo; echo "== 6 partitions spread across 3 members (2 each) =="
members

echo; echo "== drop to 2 members (scale down, so no replacement pod spawns) =="
kubectl -n "$NS" scale deploy/consumer --replicas=2
kubectl -n "$NS" rollout status deploy/consumer --timeout=120s
sleep 15

echo; echo "== the 2 survivors absorb all 6 partitions (3 each) =="
members

echo; echo "== scale back to 1 =="
kubectl -n "$NS" scale deploy/consumer --replicas=1
kubectl -n "$NS" rollout status deploy/consumer --timeout=120s
sleep 12
members
echo; echo "groups demo OK - partitions follow members, and rebalance on membership change."
