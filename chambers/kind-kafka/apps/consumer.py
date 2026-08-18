import os
import signal
import sys

from confluent_kafka import DeserializingConsumer, Producer
from confluent_kafka.error import ValueDeserializationError
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.json_schema import JSONDeserializer
from confluent_kafka.serialization import StringDeserializer

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
sasl = {
    "bootstrap.servers": os.environ["BOOTSTRAP"],
    "security.protocol": "SASL_PLAINTEXT",
    "sasl.mechanism": "SCRAM-SHA-512",
    "sasl.username": os.environ["KAFKA_USER"],
    "sasl.password": os.environ["KAFKA_PASSWORD"],
}
conf = {
    **sasl,
    "group.id": os.environ.get("GROUP", "app"),
    "auto.offset.reset": "earliest",
    "key.deserializer": StringDeserializer("utf_8"),
    "value.deserializer": JSONDeserializer(SCHEMA, from_dict=lambda d, ctx: d, schema_registry_client=sr),
}
TOPIC = os.environ.get("TOPIC", "demo")
DLQ_TOPIC = os.environ.get("DLQ_TOPIC", "demo-dlq")

consumer = DeserializingConsumer(conf)
consumer.subscribe([TOPIC])
dlq = Producer(sasl)
signal.signal(signal.SIGTERM, lambda *_: (consumer.close(), sys.exit(0)))
print(f"consuming {TOPIC} as group {conf['group.id']}", flush=True)


def to_dead_letter(err):
    # The undeserializable message is preserved on err.kafka_message; route the raw
    # bytes to the DLQ with the failure reason, then let the consumer move on.
    m = err.kafka_message
    dlq.produce(
        DLQ_TOPIC,
        key=m.key(),
        value=m.value(),
        headers=[
            ("error", str(err)[:256].encode()),
            ("origin-topic", (m.topic() or "").encode()),
            ("origin-partition", str(m.partition()).encode()),
            ("origin-offset", str(m.offset()).encode()),
        ],
    )
    dlq.flush(5)
    print(f"poison message -> {DLQ_TOPIC} (partition={m.partition()} offset={m.offset()}): {err}", flush=True)


while True:
    try:
        msg = consumer.poll(1.0)
    except ValueDeserializationError as err:
        to_dead_letter(err)
        continue
    if msg is None:
        continue
    value = msg.value()
    print(
        f"consumed key={msg.key()} partition={msg.partition()} offset={msg.offset()} seq={value['seq']}",
        flush=True,
    )
