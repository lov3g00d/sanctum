#!/usr/bin/env bash
# A model on its own is just an oracle. Tool calling is what turns it into an
# agent: it emits a structured request to run a function, you run it, feed the
# result back, and it answers using real data. This walks one full round-trip
# against a local get_weather tool. `think:false` keeps a reasoning model like
# qwen3 from narrating; the tool call is what we want to see.
set -euo pipefail

MODEL="${1:-qwen3:8b}"
HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
URL="http://$HOST/api/chat"
CITY="Berlin"

tools='[{"type":"function","function":{
  "name":"get_weather",
  "description":"Get the current weather for a city",
  "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]'

echo "1. asking $MODEL: \"What is the weather in $CITY?\" (with a get_weather tool)"
first="$(curl -s "$URL" -H 'Content-Type: application/json' -d "$(jq -n \
  --arg m "$MODEL" --arg c "$CITY" --argjson tools "$tools" '{
    model: $m, stream: false, think: false,
    messages: [{role:"user", content:("What is the weather in "+$c+"? Use the tool.")}],
    tools: $tools
  }')")"

call="$(jq -c '.message.tool_calls[0] // empty' <<<"$first")"
if [ -z "$call" ]; then
  echo "   model did not request a tool. Raw reply:"
  jq -r '.message.content' <<<"$first"
  echo "   (try a tool-capable model, e.g. task tools MODEL=qwen2.5-coder:7b)"
  exit 1
fi

name="$(jq -r '.function.name' <<<"$call")"
args="$(jq -c '.function.arguments' <<<"$call")"
echo "2. model requested: $name($args)"

# "Run" the function. A real tool would hit an API; we return a canned result.
result="$(jq -n --argjson a "$args" '{city: $a.city, temp_c: 12, sky: "overcast"}')"
echo "3. we run it locally -> $result"

echo "4. feeding the result back; model answers with real data:"
curl -s "$URL" -H 'Content-Type: application/json' -d "$(jq -n \
  --arg m "$MODEL" --arg c "$CITY" --argjson call "$call" --arg res "$result" '{
    model: $m, stream: false, think: false,
    messages: [
      {role:"user", content:("What is the weather in "+$c+"? Use the tool.")},
      {role:"assistant", tool_calls: [$call]},
      {role:"tool", tool_name:"get_weather", content: $res}
    ]
  }')" | jq -r '.message.content'
