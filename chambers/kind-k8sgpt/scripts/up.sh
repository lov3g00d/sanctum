#!/usr/bin/env bash
# Stand up the lab: a kind cluster, a deliberately broken workload for k8sgpt to
# find, and a chamber-local k8sgpt config pointing --explain at the local Ollama
# server. Nothing here touches your global k8sgpt config or kube-context: the
# backend lives in .run/k8sgpt.yaml and every kubectl/k8sgpt call names the
# kind-k8sgpt context explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

KIND_CLUSTER="${KIND_CLUSTER:-k8sgpt}"
CTX="${CTX:-kind-k8sgpt}"
NS="${NS:-k8sgpt-demo}"
CFG="${K8SGPT_CFG:-.run/k8sgpt.yaml}"
MODEL="${MODEL:-qwen2.5:7b}"
# k8sgpt's ollama backend calls the native /api/generate, so the baseurl is the
# server root, NOT the OpenAI-compatible /v1 path (which 404s here).
BASEURL="${OLLAMA_BASEURL:-http://localhost:11434}"
mkdir -p .run

if ! kind get clusters | grep -qx "$KIND_CLUSTER"; then
  kind create cluster --config kind/cluster.yaml
else
  echo "kind cluster '$KIND_CLUSTER' already exists"
fi

kubectl --context "$CTX" apply -f k8s/broken.yaml

# Configure the ollama backend in the chamber-local config (idempotent).
k8sgpt --config "$CFG" auth remove --backends ollama >/dev/null 2>&1 || true
k8sgpt --config "$CFG" auth add --backend ollama --model "$MODEL" --baseurl "$BASEURL"
echo "k8sgpt ollama backend -> $BASEURL (model: $MODEL), config: $CFG"

# Wait for the broken pod to actually reach a failure state so analyze has
# something deterministic to report.
echo -n "waiting for the broken workload to fail"
for _ in $(seq 1 40); do
  reason="$(kubectl --context "$CTX" -n "$NS" get pods -l app=broken-image \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
  case "$reason" in
    ImagePullBackOff | ErrImagePull)
      echo " -> $reason"
      exit 0
      ;;
  esac
  echo -n "."
  sleep 3
done
echo " (timed out waiting for ImagePullBackOff; analyze may show less)"
