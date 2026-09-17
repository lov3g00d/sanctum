#!/usr/bin/env bash
# Install the k8sgpt operator and apply the analysis-only K8sGPT config. The
# operator then runs continuously: it scans the cluster on an interval and writes
# each finding as a Result CRD, the in-cluster counterpart to the one-shot CLI.
set -euo pipefail
cd "$(dirname "$0")/.."

CTX="${CTX:-kind-k8sgpt}"

helm --kube-context "$CTX" repo add k8sgpt https://charts.k8sgpt.ai/ >/dev/null 2>&1 || true
helm --kube-context "$CTX" repo update k8sgpt >/dev/null
helm --kube-context "$CTX" upgrade --install release k8sgpt/k8sgpt-operator \
  -n k8sgpt-operator-system --create-namespace --wait --timeout 5m

kubectl --context "$CTX" apply -f k8s/k8sgpt-operator.yaml
echo "operator installed and configured. Findings land as Result CRDs: task operator-results"
