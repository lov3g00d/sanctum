#!/usr/bin/env bash
# k8sgpt ships an MCP server (`serve --mcp`), so Claude Code can drive its
# analyze / cluster-info / get-logs / list-resources tools directly. This prints
# the exact `claude mcp add` line; wiring your global Claude Code config stays
# your call. `serve` also binds a gRPC (8090) and metrics (8091) port even in MCP
# mode, so the ports are pinned here - two concurrent sessions would otherwise
# collide on the defaults.
set -euo pipefail
cd "$(dirname "$0")/.."

CFG="$PWD/${K8SGPT_CFG:-.run/k8sgpt.yaml}"
CTX="${CTX:-kind-k8sgpt}"
MODEL="${MODEL:-qwen2.5:7b}"

cat <<EOF
Add k8sgpt to Claude Code as an MCP server (stdio):

  claude mcp add k8sgpt -- \\
    k8sgpt --config "$CFG" --kubecontext $CTX \\
    serve --mcp --backend ollama --model $MODEL --port 8090 --metrics-port 8091

Then in a Claude Code session the model can call: analyze, cluster-info,
get-logs, get-resource, list-events, list-namespaces, list-resources, and the
filter tools - all against the kind-k8sgpt cluster.

Remove it with:  claude mcp remove k8sgpt
Run the server standalone to poke at it:
  k8sgpt --config "$CFG" --kubecontext $CTX serve --mcp --backend ollama --port 8090 --metrics-port 8091
EOF
