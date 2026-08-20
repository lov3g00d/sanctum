#!/usr/bin/env bash
# Prove the rolling deploy is zero-downtime: hammer the load balancer with a
# curl loop while the rolling deploy drains/redeploys/re-enables each web node,
# then report how many requests were served and how many were not 200.
set -euo pipefail

LB=192.168.56.10
NEW_VERSION="${1:-2.0}"
cd "$(dirname "$0")/../ansible"

codes=$(mktemp)
( for _ in $(seq 1 600); do
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 "http://$LB/" >> "$codes" 2>/dev/null || echo 000 >> "$codes"
    sleep 0.2
  done ) &
loop_pid=$!

echo "== rolling deploy to version $NEW_VERSION while curling the LB =="
ansible-playbook deploy.yml -e app_version="$NEW_VERSION"

sleep 2
kill "$loop_pid" 2>/dev/null || true
wait "$loop_pid" 2>/dev/null || true

total=$(wc -l < "$codes")
non200=$(grep -vc '^200$' "$codes" || true)
echo "== during the deploy: $total requests, $non200 non-200 =="
echo -n "== version now served: "
curl -s "http://$LB/" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version"))'
rm -f "$codes"
