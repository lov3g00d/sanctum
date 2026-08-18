import os
import signal
import sys
import time

from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.json_schema import JSONSerializer
from confluent_kafka.serialization import StringSerializer

SCHEMA = """
{
  "type": "object",
  "properties": {
    "seq": {"type": "integer"},
    "ts": {"type": "number"}
  },
  "required": ["seq", "ts"],
  "additionalProperties": false
}
"""

sr = SchemaRegistryClient({"url": os.environ["SCHEMA_REGISTRY_URL"]})

conf = {
    "bootstrap.servers": os.environ["BOOTSTRAP"],
    "security.protocol": "SASL_PLAINTEXT",
    "sasl.mechanism": "SCRAM-SHA-512",
    "sasl.username": os.environ["KAFKA_USER"],
    "sasl.password": os.environ["KAFKA_PASSWORD"],
    "acks": "all",
    "key.serializer": StringSerializer("utf_8"),
    "value.serializer": JSONSerializer(SCHEMA, sr, to_dict=lambda o, ctx: o),
}
TOPIC = os.environ.get("TOPIC", "demo")
KEYS = int(os.environ.get("KEYS", "5"))

producer = SerializingProducer(conf)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))


def delivered(err, msg):
    if err is not None:
        print(f"produce FAILED: {err}", flush=True)
        return
    key = msg.key()
    if isinstance(key, bytes):
        key = key.decode()
    print(f"produced key={key} -> partition={msg.partition()} offset={msg.offset()}", flush=True)


seq = 0
while True:
    seq += 1
    key = f"order-{seq % KEYS}"
    producer.produce(topic=TOPIC, key=key, value={"seq": seq, "ts": time.time()}, on_delivery=delivered)
    producer.poll(0)
    time.sleep(1)
