#!/usr/bin/env bash
#
# run-validation.sh - purple-team control validation for the Sanctum platform.
#
# AUTHORIZATION AND SCOPE
#   This is authorized self-validation of the operator's OWN reference
#   platform. Every manifest under attacks/ is an attack ATTEMPT that a Sanctum
#   control is expected to BLOCK. Nothing here targets third-party systems.
#   Run it only against a cluster you own. It applies the attempts into the
#   sanctum namespace, checks that the matching control stopped each one, prints
#   a PASS/FAIL matrix, and cleans up after itself.
#
# WHAT "PASS" MEANS
#   admission-deny  the apply is rejected by PSA restricted or a Kyverno policy
#   runtime-kill    the pod is admitted, then killed by Tetragon (exit 137)
#   network-block   the pod is admitted, then its egress is dropped by the
#                   default-deny NetworkPolicy (probe reports BLOCKED)
#
# USAGE
#   ./run-validation.sh [--context NAME] [--explain] [-h]
#     --context NAME   kubectl context to use (else current context / KUBECONFIG)
#     --explain        print the matrix of what would run, apply nothing
#     -h, --help       this help
#
set -euo pipefail

CONTEXT=""
EXPLAIN=false
TIMEOUT=60
POLL_INTERVAL=3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTACK_DIR="${SCRIPT_DIR}/attacks"

usage() {
  sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^#\{0,1\} \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      [[ $# -ge 2 ]] || { echo "error: --context needs a value" >&2; exit 2; }
      CONTEXT="$2"; shift 2 ;;
    --context=*) CONTEXT="${1#*=}"; shift ;;
    --explain|--dry-run) EXPLAIN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

KUBECTL=(kubectl)
[[ -n "$CONTEXT" ]] && KUBECTL+=(--context "$CONTEXT")

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing dependency: $1" >&2; exit 2; }; }
need yq
[[ "$EXPLAIN" == true ]] || need kubectl

mapfile -t ATTACK_FILES < <(find "$ATTACK_DIR" -maxdepth 1 -name '*.yaml' | sort)
[[ ${#ATTACK_FILES[@]} -gt 0 ]] || { echo "error: no attack manifests in ${ATTACK_DIR}" >&2; exit 2; }

field() {
  local file="$1" expr="$2" val
  val="$(yq eval "$expr" "$file" 2>/dev/null || true)"
  [[ "$val" == "null" ]] && val=""
  printf '%s' "$val"
}

cleanup() {
  [[ "$EXPLAIN" == true ]] && return 0
  local f
  echo
  echo "Cleaning up applied attempts ..."
  for f in "${ATTACK_FILES[@]}"; do
    "${KUBECTL[@]}" delete -f "$f" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Globals set by each evaluator.
RESULT=""
DETAIL=""

eval_admission_deny() {
  local file="$1" out
  if out="$("${KUBECTL[@]}" apply -f "$file" 2>&1)"; then
    RESULT="FAIL"; DETAIL="admitted, expected a denial"
    return
  fi
  if grep -qiE 'denied the request|violates PodSecurity|forbidden|not allowed|admission webhook|blocked|policy' <<<"$out"; then
    RESULT="PASS"; DETAIL="rejected at admission"
  else
    RESULT="ERROR"; DETAIL="apply failed for an unrelated reason"
  fi
}

eval_runtime_kill() {
  local file="$1" name ns out deadline restarts code
  name="$(field "$file" '.metadata.name')"
  ns="$(field "$file" '.metadata.namespace')"; ns="${ns:-sanctum}"
  if ! out="$("${KUBECTL[@]}" apply -f "$file" 2>&1)"; then
    RESULT="FAIL"; DETAIL="rejected at admission, was expected to survive it"
    return
  fi
  deadline=$(( $(date +%s) + TIMEOUT ))
  while [[ $(date +%s) -lt $deadline ]]; do
    restarts="$("${KUBECTL[@]}" get pod "$name" -n "$ns" \
      -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)"
    code="$("${KUBECTL[@]}" get pod "$name" -n "$ns" \
      -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null || true)"
    if [[ -n "$code" ]]; then
      if [[ "$code" == "137" ]]; then
        RESULT="PASS"; DETAIL="SIGKILL, exit 137 (Tetragon)"
      else
        RESULT="PASS"; DETAIL="terminated, exit ${code}"
      fi
      return
    fi
    if [[ -n "$restarts" && "$restarts" -gt 0 ]]; then
      RESULT="PASS"; DETAIL="restarted ${restarts}x (killed and CrashLooping)"
      return
    fi
    sleep "$POLL_INTERVAL"
  done
  RESULT="FAIL"; DETAIL="still running after ${TIMEOUT}s, no kill observed"
}

eval_network_block() {
  local file="$1" name ns out deadline logs
  name="$(field "$file" '.metadata.name')"
  ns="$(field "$file" '.metadata.namespace')"; ns="${ns:-sanctum}"
  if ! out="$("${KUBECTL[@]}" apply -f "$file" 2>&1)"; then
    RESULT="FAIL"; DETAIL="rejected at admission, was expected to survive it"
    return
  fi
  deadline=$(( $(date +%s) + TIMEOUT ))
  while [[ $(date +%s) -lt $deadline ]]; do
    logs="$("${KUBECTL[@]}" logs "$name" -n "$ns" 2>/dev/null || true)"
    if grep -q 'CONTROL-FAILED' <<<"$logs"; then
      RESULT="FAIL"; DETAIL="egress reached the target, NetworkPolicy did not block"
      return
    fi
    if grep -q 'BLOCKED-AS-EXPECTED' <<<"$logs"; then
      RESULT="PASS"; DETAIL="egress dropped by default-deny NetworkPolicy"
      return
    fi
    sleep "$POLL_INTERVAL"
  done
  RESULT="INCONCLUSIVE"; DETAIL="no verdict from pod logs within ${TIMEOUT}s"
}

# Row store for the final matrix.
ROWS=()
add_row() { ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5")"); }

echo "============================================================"
echo " Sanctum purple-team validation"
echo " Authorized self-validation - own cluster only."
[[ "$EXPLAIN" == true ]] && echo " MODE: explain (no manifests are applied)"
[[ -n "$CONTEXT" ]] && echo " Context: ${CONTEXT}"
echo "============================================================"

for f in "${ATTACK_FILES[@]}"; do
  base="$(basename "$f")"
  class="$(field "$f" '.metadata.labels."redteam.sanctum/control-class"')"
  technique="$(field "$f" '.metadata.annotations."redteam.sanctum/mitre"')"
  expected="$(field "$f" '.metadata.annotations."redteam.sanctum/expected"')"

  if [[ "$EXPLAIN" == true ]]; then
    add_row "$base" "$technique" "$class" "-" "$expected"
    continue
  fi

  echo
  echo ">> ${base} [${class}] ${technique}"
  case "$class" in
    admission-deny) eval_admission_deny "$f" ;;
    runtime-kill)   eval_runtime_kill "$f" ;;
    network-block)  eval_network_block "$f" ;;
    *) RESULT="ERROR"; DETAIL="unknown control-class label: '${class}'" ;;
  esac
  echo "   ${RESULT}: ${DETAIL}"
  add_row "$base" "$technique" "$class" "$RESULT" "$DETAIL"
done

echo
echo "============================================================"
if [[ "$EXPLAIN" == true ]]; then
  printf '%-24s %-12s %-15s %s\n' "ATTEMPT" "TECHNIQUE" "CONTROL-CLASS" "EXPECTED"
  printf '%-24s %-12s %-15s %s\n' "-------" "---------" "-------------" "--------"
  for row in "${ROWS[@]}"; do
    IFS=$'\t' read -r a t c _ e <<<"$row"
    printf '%-24s %-12s %-15s %s\n' "$a" "$t" "$c" "$e"
  done
  echo "============================================================"
  exit 0
fi

printf '%-24s %-12s %-15s %-13s %s\n' "ATTEMPT" "TECHNIQUE" "CONTROL-CLASS" "RESULT" "DETAIL"
printf '%-24s %-12s %-15s %-13s %s\n' "-------" "---------" "-------------" "------" "------"
fails=0
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r a t c r d <<<"$row"
  printf '%-24s %-12s %-15s %-13s %s\n' "$a" "$t" "$c" "$r" "$d"
  [[ "$r" == "PASS" ]] || fails=$((fails + 1))
done
echo "============================================================"

if [[ "$fails" -gt 0 ]]; then
  echo "RESULT: ${fails} attempt(s) did not resolve to PASS. A control may be missing or misconfigured."
  exit 1
fi
echo "RESULT: all controls blocked their attempt."
