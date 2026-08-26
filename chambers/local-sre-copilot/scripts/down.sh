#!/usr/bin/env bash
# Stop the copilot app services (MCP + API). Ollama is left running unless --all.
set -euo pipefail
cd "$(dirname "$0")/.."
RUN=.run

stop() {
  local name="$1"
  if [ -f "$RUN/$name.pid" ]; then
    kill -TERM -"$(cat "$RUN/$name.pid")" 2>/dev/null && echo "stopped $name" || true
    rm -f "$RUN/$name.pid"
  fi
}

stop api
stop mcp

if [ "${1:-}" = "--all" ]; then
  stop ollama
fi
