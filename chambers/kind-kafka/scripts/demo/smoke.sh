#!/usr/bin/env bash
# Produce and consume on a topic (default: demo), authenticated as admin.
#   ./smoke.sh [topic]
set -euo pipefail
NS=kafka
TOPIC="${1:-demo}"

PW=$(kubectl -n "$NS" get secret admin -o jsonpath='{.data.password}' | base64 -d)
POD=$(kubectl -n "$NS" get pod -l strimzi.io/cluster=sanctum,strimzi.io/broker-role=true \
  -o jsonpath='{.items[0].metadata.name}')
echo "using pod: $POD (topic: $TOPIC)"

kubectl -n "$NS" exec -i "$POD" -- bash -s "$TOPIC" "$PW" <<'REMOTE'
set -e
TOPIC="$1"; PW="$2"
cat > /tmp/admin.props <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="${PW}";
EOF
echo "== producing 5 messages to $TOPIC =="
for i in 1 2 3 4 5; do echo "hello-$i"; done \
  | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 \
      --topic "$TOPIC" --producer.config /tmp/admin.props
echo "== consuming 5 messages from $TOPIC =="
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" \
  --from-beginning --max-messages 5 --timeout-ms 20000 --consumer.config /tmp/admin.props
REMOTE
echo "smoke test OK"
