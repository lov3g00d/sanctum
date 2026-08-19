#!/usr/bin/env bash
# Canary: shift traffic from v1 to v2 in steps and, at each step, sample the
# ingress to show the observed split matching the configured weights.
set -euo pipefail
NS=web
GW=http://localhost:18081

setweights() { # v1 v2
  kubectl -n "$NS" patch virtualservice web --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/http/0/route/0/weight\",\"value\":$1},{\"op\":\"replace\",\"path\":\"/spec/http/0/route/1/weight\",\"value\":$2}]" >/dev/null
}

sample() { # count
  local v1=0 v2=0 v
  for _ in $(seq 1 "$1"); do
    v=$(curl -s --max-time 3 "$GW/" | jq -r '.version' 2>/dev/null || echo "?")
    if [ "$v" = v1 ]; then v1=$((v1 + 1)); elif [ "$v" = v2 ]; then v2=$((v2 + 1)); fi
  done
  echo "  observed: v1=$v1  v2=$v2  (of $1 requests)"
}

for split in "90 10" "50 50" "0 100"; do
  set -- $split
  echo "== shift weights to v1=$1%  v2=$2% =="
  setweights "$1" "$2"
  sleep 3
  sample 50
done
echo "canary demo OK (run 'task reset' to route 100% back to v1)"
