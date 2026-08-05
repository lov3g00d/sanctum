#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: health-check.sh BASE_URL [TIMEOUT_SECONDS]

Probes a Sanctum service liveness (/healthz) and readiness (/readyz) endpoints.
Retries with exponential backoff and exits non-zero if either stays unhealthy.
Suitable as an external uptime / synthetic check.

Arguments:
  BASE_URL          Service base URL, e.g. https://api.sanctum.example.com
  TIMEOUT_SECONDS   Per-request curl timeout (default: 5)

Environment:
  HEALTH_MAX_ATTEMPTS   Retry attempts per endpoint (default: 4)
  HEALTH_BASE_DELAY     Initial backoff seconds (default: 1)
EOF
}

cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    log ERROR "health-check exited with status ${rc}"
  fi
}
trap cleanup EXIT

main() {
  if (( $# < 1 )) || [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 2
  fi

  local base_url="$1"
  local timeout="${2:-5}"
  local max_attempts="${HEALTH_MAX_ATTEMPTS:-4}"
  local base_delay="${HEALTH_BASE_DELAY:-1}"

  require_cmd curl

  base_url="${base_url%/}"

  local endpoint
  for endpoint in /healthz /readyz; do
    local url="${base_url}${endpoint}"
    log INFO "probing ${url}"
    if retry_with_backoff "$max_attempts" "$base_delay" \
      curl --fail --silent --show-error --max-time "$timeout" -o /dev/null "$url"; then
      log INFO "OK ${url}"
    else
      die "unhealthy: ${url}"
    fi
  done

  log INFO "all probes healthy: ${base_url}"
}

main "$@"
