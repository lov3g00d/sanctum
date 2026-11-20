#!/usr/bin/env bash
# Deterministic PASS/FAIL check that the stack ingests and serves a trace,
# independent of the local-llm server. Emits a trace through the SDK, then reads
# it back through the public API by id. Ingestion is async (SDK -> redis -> worker
# -> clickhouse), so the read is polled. Failures name which half broke.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "no .env; run 'task up' first" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
. ./.env
set +a

HOST="http://localhost:3000"
PK="$LANGFUSE_INIT_PROJECT_PUBLIC_KEY"
SK="$LANGFUSE_INIT_PROJECT_SECRET_KEY"

fail() { echo; echo "$1 FAIL"; exit 1; }

if ! curl -sf --max-time 3 "$HOST/api/public/health" >/dev/null 2>&1; then
  fail "stack health check (is it up? run 'task up'):"
fi

name="sanctum-selftest-$(date +%s)"
export LANGFUSE_HOST="$HOST"
export LANGFUSE_PUBLIC_KEY="$PK"
export LANGFUSE_SECRET_KEY="$SK"
export SELFTEST_NAME="$name"

trace_id="$(uv run python - <<'PY'
import os
from langfuse import get_client

lf = get_client()
with lf.start_as_current_observation(
    name=os.environ["SELFTEST_NAME"], as_type="span", output="selftest"
) as span:
    tid = span.trace_id
lf.flush()
print(tid)
PY
)"
trace_id="$(printf '%s\n' "$trace_id" | tail -n1)"
[ -n "$trace_id" ] || fail "SDK did not return a trace id:"

echo "emitted trace $trace_id; polling the public API for it (up to 30s)..."
landed=""
for _ in $(seq 1 15); do
  n="$(curl -s -u "$PK:$SK" "$HOST/api/public/v2/observations?traceId=$trace_id" | jq -r '(.data | length) // 0')"
  if [ "${n:-0}" -ge 1 ]; then
    landed=1
    break
  fi
  sleep 2
done

[ -n "$landed" ] || fail "trace emitted but never served by the API (ingestion pipeline: worker/clickhouse):"

echo
echo "round-trip: SDK -> stack -> public API returned the trace. PASS"
