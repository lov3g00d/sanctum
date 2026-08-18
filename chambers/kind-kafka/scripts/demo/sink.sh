#!/usr/bin/env bash
# Sink a JSON topic into Postgres with Kafka Connect, no application code: seed a
# few order records into connect-orders and read them back from the orders table
# the Debezium JDBC sink created. Messages carry the JsonConverter envelope
# (schema + payload) so the sink knows how to build the table.
set -euo pipefail
NS=kafka
BPOD=$(kubectl -n "$NS" get pod -l strimzi.io/broker-role=true -o jsonpath='{.items[0].metadata.name}')
PGPOD=$(kubectl -n "$NS" get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')
PW=$(kubectl -n "$NS" get secret admin -o jsonpath='{.data.password}' | base64 -d)

kubectl -n "$NS" exec -i "$BPOD" -- bash -c 'cat > /tmp/admin.props' <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="$PW";
EOF

# start clean so a re-run shows three rows, not duplicates (the sink recreates the table)
kubectl -n "$NS" exec "$PGPOD" -- env PGPASSWORD=connect psql -U connect -d orders -c 'DROP TABLE IF EXISTS orders;' >/dev/null 2>&1

SCHEMA='{"type":"struct","optional":false,"name":"order","fields":[{"field":"id","type":"int32","optional":false},{"field":"item","type":"string","optional":false},{"field":"qty","type":"int32","optional":false}]}'
echo "== seed 3 orders into connect-orders =="
{
  printf '{"schema":%s,"payload":{"id":1,"item":"widget","qty":3}}\n' "$SCHEMA"
  printf '{"schema":%s,"payload":{"id":2,"item":"gadget","qty":7}}\n' "$SCHEMA"
  printf '{"schema":%s,"payload":{"id":3,"item":"gizmo","qty":1}}\n' "$SCHEMA"
} | kubectl -n "$NS" exec -i "$BPOD" -- /opt/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server localhost:9092 --topic connect-orders --producer.config /tmp/admin.props

echo "== wait for the sink to create the table and flush the rows =="
count() { kubectl -n "$NS" exec "$PGPOD" -- env PGPASSWORD=connect psql -U connect -d orders -tAc 'SELECT count(*) FROM orders' 2>/dev/null | tr -d '[:space:]'; }
for i in $(seq 1 20); do [ "$(count)" = "3" ] && break; sleep 3; done

echo "== the orders table Kafka Connect populated in Postgres =="
kubectl -n "$NS" exec "$PGPOD" -- env PGPASSWORD=connect \
  psql -U connect -d orders -c 'SELECT * FROM orders ORDER BY id;'
echo "sink demo OK"
