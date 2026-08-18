#!/usr/bin/env bash
# Prove replication survives a broker loss (authenticated as admin).
#   ./ha-demo.sh [topic] [count]
set -euo pipefail
NS=kafka
TOPIC="${1:-demo}"
N="${2:-50}"

brokers() {
  kubectl -n "$NS" get pod -l strimzi.io/cluster=sanctum,strimzi.io/broker-role=true \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}
KILL=$(brokers | head -1)
SURVIVOR=$(brokers | sed -n 2p)
PW=$(kubectl -n "$NS" get secret admin -o jsonpath='{.data.password}' | base64 -d)

# admin SASL config, written once into the surviving pod (persists across execs)
kubectl -n "$NS" exec -i "$SURVIVOR" -- bash -c 'cat > /tmp/admin.props' <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="$PW";
EOF
CFG="--command-config /tmp/admin.props"
KT=/opt/kafka/bin/kafka-topics.sh

echo "== topic layout: replication factor 3, ISR = 3 per partition =="
kubectl -n "$NS" exec "$SURVIVOR" -- $KT --bootstrap-server localhost:9092 --describe --topic "$TOPIC" $CFG

echo; echo "== produce $N messages with acks=all =="
kubectl -n "$NS" exec -i "$SURVIVOR" -- bash -s "$TOPIC" "$N" <<'REMOTE'
TOPIC="$1"; N="$2"
for i in $(seq 1 "$N"); do echo "msg-$i"; done \
  | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 \
      --topic "$TOPIC" --producer-property acks=all --producer.config /tmp/admin.props
echo "produced $N"
REMOTE

echo; echo "== KILL a broker: $KILL =="
kubectl -n "$NS" delete pod "$KILL" --wait=false
sleep 12

echo; echo "== layout while $KILL is down: leaders moved off it =="
kubectl -n "$NS" exec "$SURVIVOR" -- $KT --bootstrap-server localhost:9092 --describe --topic "$TOPIC" $CFG

echo; echo "== consume everything from a surviving broker =="
GOT=$(kubectl -n "$NS" exec "$SURVIVOR" -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic "$TOPIC" \
  --from-beginning --timeout-ms 15000 --consumer.config /tmp/admin.props 2>/dev/null \
  | grep -c '^msg-' || true)
echo; echo "produced=$N  consumed=$GOT"
[ "$GOT" = "$N" ] && echo "NO DATA LOST - the dead broker held replicas, not the only copy." \
  || echo "MISMATCH - investigate."
