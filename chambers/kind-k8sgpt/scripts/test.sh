#!/usr/bin/env bash
# Deterministic check: k8sgpt's analysis (no LLM) must find the two planted
# faults. Uses `analyze -o json` so it never calls the model, which keeps this a
# reproducible PASS/FAIL gate. The --explain path (task explain) is the LLM layer
# and is intentionally not asserted here.
set -euo pipefail
cd "$(dirname "$0")/.."

CFG="${K8SGPT_CFG:-.run/k8sgpt.yaml}"
CTX="${CTX:-kind-k8sgpt}"
NS="${NS:-k8sgpt-demo}"

json="$(k8sgpt --config "$CFG" --kubecontext "$CTX" analyze -n "$NS" -o json 2>/dev/null)"

# kind|||name-substring that must appear in a result
CASES=(
  "Pod|||broken-image"
  "Service|||orphan-svc"
)

printf '\n%-10s %-24s %s\n' "KIND" "EXPECTED (contains)" "RESULT"
printf '%s\n' "------------------------------------------------------------"
fails=0
for case in "${CASES[@]}"; do
  kind="${case%%|||*}"
  name="${case##*|||}"
  if jq -e --arg k "$kind" --arg n "$name" \
      '.results[]? | select(.kind == $k and (.name | contains($n)))' >/dev/null 2>&1 <<<"$json"; then
    result="PASS"
  else
    result="FAIL (not detected)"
    fails=$((fails + 1))
  fi
  printf '%-10s %-24s %s\n' "$kind" "$name" "$result"
done

total="$(jq -r '.problems // 0' <<<"$json" 2>/dev/null || echo '?')"
echo
if [ "$fails" -eq 0 ]; then
  echo "k8sgpt detected both planted faults (${total} problems total). PASS"
else
  echo "$fails/${#CASES[@]} planted faults were not detected. FAIL"
  exit 1
fi
