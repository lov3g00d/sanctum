#!/usr/bin/env bash
# Same prompt, two models, so you can judge the quality/speed trade for your
# own work rather than trusting a benchmark table. Pulls a model if it is not
# already present.
set -euo pipefail

A="${1:-qwen3:4b}"
B="${2:-qwen3:8b}"
HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
PROMPT="Explain the difference between a process and a thread to a junior engineer, in 3 sentences."

run() {
  local model="$1"
  ollama pull "$model" >/dev/null 2>&1 || true
  echo "=============================================================="
  echo "MODEL: $model"
  echo "=============================================================="
  local resp
  resp="$(curl -s "http://$HOST/api/generate" -H 'Content-Type: application/json' -d "$(jq -n \
    --arg m "$model" --arg p "$PROMPT" '{model:$m, prompt:$p, stream:false, think:false}')")"
  jq -r '.response' <<<"$resp"
  jq -r '"[decode \((.eval_count // 0) / ((.eval_duration // 1) / 1e9) | floor) tok/s]"' <<<"$resp"
  echo
}

echo "prompt: $PROMPT"
echo
run "$A"
run "$B"
