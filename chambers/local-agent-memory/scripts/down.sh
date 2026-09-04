#!/usr/bin/env bash
# Remove the generated palace and the config init writes into the corpus dir.
# Keeps corpus/ (committed inputs) and .venv/. Pass --clean to also drop the venv.
set -euo pipefail
cd "$(dirname "$0")/.."

PALACE="${PALACE:-.palace}"
CORPUS="${CORPUS:-corpus}"

rm -rf "$PALACE" "$CORPUS/mempalace.yaml" "$CORPUS/.mempalace"
echo "removed $PALACE and generated config in $CORPUS"

if [ "${1:-}" = "--clean" ]; then
  rm -rf .venv
  echo "removed .venv"
fi
