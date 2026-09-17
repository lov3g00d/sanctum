#!/usr/bin/env bash
# Remove the K8sGPT config, the operator release, and its namespace. Leaves the
# kind cluster and the broken workload in place (use `task down` for those).
set -euo pipefail
cd "$(dirname "$0")/.."

CTX="${CTX:-kind-k8sgpt}"

kubectl --context "$CTX" delete -f k8s/k8sgpt-operator.yaml --ignore-not-found
helm --kube-context "$CTX" uninstall release -n k8sgpt-operator-system 2>/dev/null || true
kubectl --context "$CTX" delete ns k8sgpt-operator-system --ignore-not-found
echo "operator removed"
