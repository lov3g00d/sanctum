#!/usr/bin/env bash
# Blue-green: flip 100% of traffic from v1 (blue) to v2 (green) in one step, then
# roll back. No request is split; the whole fleet cuts over at once.
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

echo "== blue: 100% v1 =="
setweights 100 0
sleep 2
sample 30
echo "== cut over to green: 100% v2 (one step) =="
setweights 0 100
sleep 2
sample 30
echo "== roll back to blue: 100% v1 =="
setweights 100 0
sleep 2
sample 30
echo "bluegreen demo OK"
