#!/usr/bin/env bash
# Change data capture: change a row in Postgres and watch Debezium stream the
# change into Kafka as a CDC event. The topic already holds the initial snapshot
# of the table (op=r); the update shows up as op=u. Reads the topic as admin.
set -euo pipefail
NS=kafka
CDC_TOPIC=orders-server.public.orders
BPOD=$(kubectl -n "$NS" get pod -l strimzi.io/broker-role=true -o jsonpath='{.items[0].metadata.name}')
PGPOD=$(kubectl -n "$NS" get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')
PW=$(kubectl -n "$NS" get secret admin -o jsonpath='{.data.password}' | base64 -d)

kubectl -n "$NS" exec -i "$BPOD" -- bash -c 'cat > /tmp/admin.props' <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="$PW";
EOF

# the sink builds orders without a primary key; REPLICA IDENTITY FULL lets Postgres
# publish updates for it (logs the whole row), which logical replication needs.
# Set it before the source starts so its publication captures updates. Needs the
# orders table to exist first (run `task sink`).
echo "== enable full row logging on orders, then start the Debezium Postgres source =="
kubectl -n "$NS" exec "$PGPOD" -- env PGPASSWORD=connect \
  psql -U connect -d orders -c 'ALTER TABLE orders REPLICA IDENTITY FULL;'
kubectl -n "$NS" apply -f connect/source.yaml >/dev/null
kubectl -n "$NS" wait --for=condition=Ready kafkaconnector/orders-source --timeout=180s

echo "== change a row in Postgres: set qty=99 for order 1 =="
kubectl -n "$NS" exec "$PGPOD" -- env PGPASSWORD=connect \
  psql -U connect -d orders -c 'UPDATE orders SET qty = 99 WHERE id = 1;'

echo "== give Debezium a moment to capture it =="
sleep 6

echo "== CDC events Debezium streamed to $CDC_TOPIC (op: r=snapshot, c=create, u=update, d=delete) =="
kubectl -n "$NS" exec "$BPOD" -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic "$CDC_TOPIC" --from-beginning \
  --timeout-ms 15000 --consumer.config /tmp/admin.props 2>/dev/null \
  | jq -rR 'fromjson? | if .payload then "op=\(.payload.op)  after=\(.payload.after // "null")" else empty end'
echo "cdc demo OK"
