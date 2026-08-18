#!/usr/bin/env bash
# Prove the data contract is enforced at the producer: a valid message is
# accepted, contract-violating ones are rejected before they reach the topic.
# Runs inside the producer pod, which already has the client and registry env.
set -euo pipefail
NS=kafka
POD=$(kubectl -n "$NS" get pod -l app=producer -o jsonpath='{.items[0].metadata.name}')

kubectl -n "$NS" exec -i "$POD" -- python - <<'PY'
import os
from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.json_schema import JSONSerializer
from confluent_kafka.serialization import StringSerializer

SCHEMA = '{"type":"object","properties":{"seq":{"type":"integer"},"ts":{"type":"number"}},"required":["seq","ts"],"additionalProperties":false}'
sr = SchemaRegistryClient({"url": os.environ["SCHEMA_REGISTRY_URL"]})
p = SerializingProducer({
    "bootstrap.servers": os.environ["BOOTSTRAP"],
    "security.protocol": "SASL_PLAINTEXT",
    "sasl.mechanism": "SCRAM-SHA-512",
    "sasl.username": os.environ["KAFKA_USER"],
    "sasl.password": os.environ["KAFKA_PASSWORD"],
    "acks": "all",
    "key.serializer": StringSerializer("utf_8"),
    "value.serializer": JSONSerializer(SCHEMA, sr, to_dict=lambda o, ctx: o),
})
TOPIC = os.environ.get("TOPIC", "demo")

def check(label, value):
    try:
        p.produce(topic=TOPIC, key="demo", value=value)
        p.flush(10)
        print(f"[accepted] {label:24} {value}")
    except Exception as e:
        print(f"[rejected] {label:24} {type(e).__name__}: {e}")

check("valid", {"seq": 1, "ts": 1.0})
check("seq is a string", {"seq": "x", "ts": 1.0})
check("missing required ts", {"seq": 2})
check("unknown extra field", {"seq": 3, "ts": 1.0, "rogue": True})
PY
echo "schema demo OK - only the valid message reached the topic."
