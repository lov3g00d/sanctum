#!/usr/bin/env bash
# Start the Ollama server if nothing is serving yet, then pull the requested
# model. The server is started in its own process group (setsid) with its pid
# recorded, so down.sh can stop exactly the process this chamber started and
# never kill an Ollama the user is running for something else.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:-qwen3:8b}"
HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
RUN=.run
mkdir -p "$RUN"

if ! curl -s --max-time 2 "http://$HOST/api/version" >/dev/null 2>&1; then
  echo "starting ollama serve (log: $RUN/ollama.log)..."
  setsid ollama serve >"$RUN/ollama.log" 2>&1 </dev/null &
  echo $! >"$RUN/ollama.pid"
  until curl -s --max-time 2 "http://$HOST/api/version" >/dev/null 2>&1; do sleep 1; done
else
  echo "ollama already serving at $HOST"
fi

echo "pulling $MODEL (skipped if already present)..."
ollama pull "$MODEL"
