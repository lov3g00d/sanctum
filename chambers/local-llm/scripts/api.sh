#!/usr/bin/env bash
# The whole point of a local server: it speaks the OpenAI wire format, so any
# OpenAI client (SDKs, Open WebUI, coding agents) points at it unchanged. This
# hits the same /v1/chat/completions path OpenAI exposes, just on localhost.
set -euo pipefail

MODEL="${1:-qwen3:8b}"
HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
URL="http://$HOST/v1/chat/completions"

echo "POST $URL   (model: $MODEL)"
echo
resp="$(curl -s "$URL" \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer ollama' \
  -d "$(jq -n --arg m "$MODEL" '{
        model: $m,
        messages: [{role: "user", content: "In one sentence, what is an OpenAI-compatible API?"}],
        stream: false
      }')")"

echo "$resp" | jq -r '.choices[0].message.content'
echo
echo "tokens: prompt=$(jq -r '.usage.prompt_tokens' <<<"$resp")  completion=$(jq -r '.usage.completion_tokens' <<<"$resp")"
