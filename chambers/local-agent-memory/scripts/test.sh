#!/usr/bin/env bash
# Deterministic recall check: fixed corpus in, fixed queries, PASS/FAIL matrix out.
# Each query must return its matching corpus file as the top hit. Same PASS/FAIL
# shape as shared/redteam/run-validation.sh. Exits non-zero if any query misses,
# so it works as a gate.
set -euo pipefail
cd "$(dirname "$0")/.."

PALACE="${PALACE:-.palace}"

# Build the palace if it hasn't been built yet.
if [ ! -d "$PALACE" ]; then
  echo "palace not built; building from corpus first..."
  scripts/build.sh
fi

# query|||expected top-hit source filename
CASES=(
  "why did the checkout endpoint get slow|||incident-2031-checkout-latency.md"
  "reason we moved the mobile api to graphql|||adr-0007-rest-to-graphql.md"
  "how do I safely restart a kafka broker|||runbook-kafka-broker-restart.md"
)

top_source() { # print the Source filename of the first result for a query
  uv run mempalace --palace "$PALACE" search "$1" --results 1 2>/dev/null \
    | grep -m1 'Source:' | awk '{print $2}'
}

printf '\n%-52s %-38s %s\n' "QUERY" "TOP HIT" "RESULT"
printf '%s\n' "----------------------------------------------------------------------------------------------------"
fails=0
for case in "${CASES[@]}"; do
  query="${case%%|||*}"
  want="${case##*|||}"
  got="$(top_source "$query")"
  if [ "$got" = "$want" ]; then
    result="PASS"
  else
    result="FAIL (got: ${got:-none})"
    fails=$((fails + 1))
  fi
  printf '%-52s %-38s %s\n' "${query:0:50}" "$want" "$result"
done

echo
if [ "$fails" -eq 0 ]; then
  echo "recall: ${#CASES[@]}/${#CASES[@]} queries returned the right memory. PASS"
else
  echo "recall: $fails/${#CASES[@]} queries missed. FAIL"
  exit 1
fi
