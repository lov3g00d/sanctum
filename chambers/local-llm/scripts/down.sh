#!/usr/bin/env bash
# Stop only the Ollama server this chamber started (tracked by .run/ollama.pid).
# If Ollama was already running when `task up` ran, there is no pidfile and we
# leave it alone. Pulled models stay on disk; delete them with `ollama rm`.
set -euo pipefail
cd "$(dirname "$0")/.."

RUN=.run
if [ -f "$RUN/ollama.pid" ]; then
  pid="$(cat "$RUN/ollama.pid")"
  echo "stopping ollama serve (pgid $pid)..."
  kill -TERM -"$pid" 2>/dev/null || true
  rm -f "$RUN/ollama.pid"
else
  echo "no chamber-started ollama to stop (it was already running, or never started)"
fi
