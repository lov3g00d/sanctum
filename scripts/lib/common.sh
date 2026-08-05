# shellcheck shell=bash
#
# Sourced helper library for the Nimbus scripts. It intentionally omits the
# strict-mode header and traps that the standalone scripts carry: a library
# must not mutate the caller's shell options or install its own traps. The
# sourcing script owns `set -euo pipefail`, IFS, and cleanup.

log() {
  local level="$1"
  shift
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s [%s] %s\n' "$ts" "$level" "$*" >&2
}

die() {
  log ERROR "$*"
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
  done
}

# retry_with_backoff MAX_ATTEMPTS BASE_DELAY_SECONDS CMD [ARGS...]
# Exponential backoff. The command is run as a tested condition so a failure
# does not trip the caller's `set -e` before the retry loop can react.
retry_with_backoff() {
  local max_attempts="$1"
  local delay="$2"
  shift 2

  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= max_attempts )); then
      log ERROR "command failed after ${attempt} attempts: $*"
      return 1
    fi
    log WARN "attempt ${attempt}/${max_attempts} failed, retrying in ${delay}s: $*"
    sleep "$delay"
    attempt=$(( attempt + 1 ))
    delay=$(( delay * 2 ))
  done
}
