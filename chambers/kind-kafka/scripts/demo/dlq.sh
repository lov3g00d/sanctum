#!/usr/bin/env bash
# Send a poison message (raw bytes, no schema envelope) to demo. The consumer
# cannot deserialize it, so instead of crashing it routes the message to the DLQ.
# Authenticated as admin.
set -euo pipefail
NS=kafka
POD=$(kubectl -n "$NS" get pod -l strimzi.io/broker-role=true -o jsonpath='{.items[0].metadata.name}')
PW=$(kubectl -n "$NS" get secret admin -o jsonpath='{.data.password}' | base64 -d)

kubectl -n "$NS" exec -i "$POD" -- bash -c 'cat > /tmp/admin.props' <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="$PW";
EOF

echo "== send a poison message (not schema-encoded) to demo =="
kubectl -n "$NS" exec -i "$POD" -- bash -c \
  'echo "not-a-valid-schema-message" | /opt/kafka/bin/kafka-console-producer.sh \
     --bootstrap-server localhost:9092 --topic demo --producer.config /tmp/admin.props'

echo "== give the consumer a moment to route it =="
sleep 8

echo "== the poison message landed in demo-dlq, with failure headers =="
kubectl -n "$NS" exec "$POD" -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic demo-dlq --from-beginning \
  --max-messages 1 --timeout-ms 15000 --property print.headers=true \
  --consumer.config /tmp/admin.props 2>/dev/null

echo "== the consumer is still alive (no crash, 0 restarts) =="
kubectl -n "$NS" get pod -l app=consumer -o jsonpath='{.items[0].metadata.name}: restarts={.items[0].status.containerStatuses[0].restartCount} status={.items[0].status.phase}{"\n"}'
echo "DLQ demo OK"
