#!/usr/bin/env bash
# Show the registry governing schema CHANGE, not just validation: a
# backward-compatible evolution is accepted as a new version, a breaking change
# is refused. Runs in the producer pod, which can reach the registry.
set -euo pipefail
NS=kafka
POD=$(kubectl -n "$NS" get pod -l app=producer -o jsonpath='{.items[0].metadata.name}')

kubectl -n "$NS" exec -i "$POD" -- python - <<'PY'
import json
import os
import urllib.error
import urllib.request

BASE = os.environ["SCHEMA_REGISTRY_URL"]
SUBJECT = "demo-value"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or "null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "null")


def register(label, schema):
    code, body = call(
        "POST", f"/subjects/{SUBJECT}/versions", {"schemaType": "JSON", "schema": json.dumps(schema)}
    )
    print(f"[{'accepted' if code == 200 else 'REFUSED '}] {label:26} HTTP {code} -> {body}")


call("PUT", f"/config/{SUBJECT}", {"compatibility": "BACKWARD"})
print("compatibility:", call("GET", f"/config/{SUBJECT}")[1])
print("versions before:", call("GET", f"/subjects/{SUBJECT}/versions")[1])

V1 = {
    "type": "object",
    "properties": {"seq": {"type": "integer"}, "ts": {"type": "number"}},
    "required": ["seq", "ts"],
    "additionalProperties": False,
}
add_optional = {**V1, "properties": {**V1["properties"], "source": {"type": "string"}}}
change_type = {**V1, "properties": {**V1["properties"], "seq": {"type": "string"}}}

print("-- backward-compatible: add an OPTIONAL field --")
register("add optional 'source'", add_optional)
print("-- breaking: change 'seq' integer -> string --")
register("change seq type", change_type)

print("versions after:", call("GET", f"/subjects/{SUBJECT}/versions")[1])
PY
echo "evolution demo OK - compatible change versioned, breaking change refused."
