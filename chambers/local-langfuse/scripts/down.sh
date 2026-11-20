#!/usr/bin/env bash
# Stop the Langfuse stack. Default keeps the volumes and .env so `task up` brings
# the same project, keys, and traces back. Pass --clean to also delete the
# volumes (postgres, clickhouse, redis, minio) and the generated .env for a
# from-scratch reset.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--clean" ]; then
  docker compose down -v
  rm -f .env
  rm -rf .venv
  echo "removed volumes, .env, and .venv"
else
  docker compose down
  echo "stack stopped; volumes and .env kept (task up restores state, task down --clean wipes it)"
fi
