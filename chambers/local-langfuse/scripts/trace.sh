#!/usr/bin/env bash
# Send one instrumented chat completion to the local-llm Ollama server and let
# the langfuse.openai wrapper trace it into the stack. Needs the local-llm
# chamber's server running; this chamber deliberately does not start it.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "no .env; run 'task up' first" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
. ./.env
set +a

OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
if ! curl -sf --max-time 2 "http://${OLLAMA_HOST}/api/version" >/dev/null 2>&1; then
  echo "no Ollama server at ${OLLAMA_HOST}. Start the substrate first:" >&2
  echo "    (cd ../local-llm && task up)" >&2
  exit 1
fi

MODEL="${MODEL:-$(curl -s "http://${OLLAMA_HOST}/api/tags" \
  | jq -r 'first(.models[].name | select(endswith("-cloud") | not)) // (.models[0].name) // empty')}"
if [ -z "$MODEL" ]; then
  echo "Ollama is running but has no models pulled. In ../local-llm run 'task up'." >&2
  exit 1
fi
echo "tracing a call to '${MODEL}' on ${OLLAMA_HOST}..."

export OLLAMA_HOST MODEL
export LANGFUSE_HOST="http://localhost:3000"
export LANGFUSE_PUBLIC_KEY="$LANGFUSE_INIT_PROJECT_PUBLIC_KEY"
export LANGFUSE_SECRET_KEY="$LANGFUSE_INIT_PROJECT_SECRET_KEY"

uv run python trace.py
