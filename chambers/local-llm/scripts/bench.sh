#!/usr/bin/env bash
# What does this model actually feel like on THIS hardware? Ollama returns
# timing counters on a non-streamed generate: prompt_eval_* is prefill (reading
# your prompt), eval_* is decode (writing the answer). Decode tok/s is the
# number you feel while it types. On a GPU-less box expect single-to-low-double
# digits; that is the honest cost of running with no accelerator.
set -euo pipefail

MODEL="${1:-qwen3:8b}"
HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

echo "benchmarking $MODEL (first run also loads the model into memory)..."
resp="$(curl -s "http://$HOST/api/generate" -H 'Content-Type: application/json' -d "$(jq -n \
  --arg m "$MODEL" '{
    model: $m, stream: false, think: false,
    prompt: "Write a haiku about running language models on your own laptop."
  }')")"

jq -r '
  def tps(count; ns): if (ns // 0) > 0 then (count / (ns / 1e9)) else 0 end;
  "prompt tokens : \(.prompt_eval_count // 0)  (prefill \(tps(.prompt_eval_count // 0; .prompt_eval_duration) | floor) tok/s)",
  "output tokens : \(.eval_count // 0)  (decode  \(tps(.eval_count // 0; .eval_duration) | floor) tok/s)",
  "load time     : \(((.load_duration // 0) / 1e9) * 100 | round / 100)s",
  "",
  .response
' <<<"$resp"
