#!/usr/bin/env bash
# Delete the kind cluster and the chamber-local k8sgpt config.
set -euo pipefail
cd "$(dirname "$0")/.."

KIND_CLUSTER="${KIND_CLUSTER:-k8sgpt}"
kind delete cluster --name "$KIND_CLUSTER"
rm -rf .run
echo "deleted cluster '$KIND_CLUSTER' and .run"
