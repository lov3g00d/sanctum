#!/usr/bin/env bash
# Bring up the SRE copilot: Ollama (+ models), ingest the corpus, then the MCP server and
# the API. Each service runs in its own process group (setsid) so it can be
# stopped cleanly by group. Ollama is left running across restarts.
set -euo pipefail
cd "$(dirname "$0")/.."
RUN=.run
mkdir -p "$RUN"
CHAT_MODEL="${COPILOT_CHAT_MODEL:-qwen2.5:7b}"

stop() { # stop a service by its process group, if the pidfile exists
  local name="$1"
  if [ -f "$RUN/$name.pid" ]; then
    kill -TERM -"$(cat "$RUN/$name.pid")" 2>/dev/null || true
    rm -f "$RUN/$name.pid"
  fi
}

# Ollama: start only if not already serving.
if ! curl -s --max-time 2 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
  echo "starting ollama serve..."
  setsid ollama serve >"$RUN/ollama.log" 2>&1 < /dev/null &
  echo $! > "$RUN/ollama.pid"
  until curl -s --max-time 2 http://127.0.0.1:11434/api/version >/dev/null 2>&1; do sleep 1; done
fi

echo "pulling models ($CHAT_MODEL + nomic-embed-text)..."
ollama pull nomic-embed-text >/dev/null
ollama pull "$CHAT_MODEL" >/dev/null

echo "syncing python deps..."
uv sync --python "$(which python3.12)" >/dev/null

# The Qdrant store is single-writer: stop the app services before ingesting.
stop api
stop mcp
sleep 1

echo "ingesting corpus..."
uv run python -m app.ingest

echo "starting MCP server (:8808)..."
setsid uv run python -m app.mcp_server >"$RUN/mcp.log" 2>&1 < /dev/null &
echo $! > "$RUN/mcp.pid"
until curl -s --max-time 2 http://127.0.0.1:8808/mcp >/dev/null 2>&1; do sleep 1; done

echo "starting API (:8809)..."
setsid uv run uvicorn app.api:app --host 127.0.0.1 --port 8809 >"$RUN/api.log" 2>&1 < /dev/null &
echo $! > "$RUN/api.pid"
until curl -s --max-time 2 http://127.0.0.1:8809/healthz >/dev/null 2>&1; do sleep 1; done

echo "copilot up. API http://127.0.0.1:8809 (POST /chat) | MCP :8808 | model $CHAT_MODEL"
