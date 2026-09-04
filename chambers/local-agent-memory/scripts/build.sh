#!/usr/bin/env bash
# Build the palace from the committed corpus: detect structure (heuristics only,
# no LLM), then mine the files in. Idempotent - mining an already-filed corpus
# refiles nothing. The first mine downloads the ~30 MB embedding model.
set -euo pipefail
cd "$(dirname "$0")/.."

PALACE="${PALACE:-.palace}"
CORPUS="${CORPUS:-corpus}"
WING="${WING:-sanctum}"

# init ends with an interactive "Mine now? [Y/n]" prompt; feed it EOF so `task up`
# never blocks on a tty. We mine explicitly on the next line regardless.
uv run mempalace --palace "$PALACE" init "$CORPUS" --yes --no-llm </dev/null
uv run mempalace --palace "$PALACE" mine "$CORPUS" --wing "$WING"
