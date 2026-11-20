#!/usr/bin/env bash
# Stand up the self-hosted Langfuse stack (postgres, clickhouse, redis, minio,
# web, worker) via docker compose. Secrets are generated once into .env and
# reused on every later run: ENCRYPTION_KEY protects rows already written to the
# database, so regenerating it against an existing volume would silently corrupt
# reads. `down --clean` is the only thing that drops both the volumes and .env.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v docker >/dev/null 2>&1 || { echo "docker not found on PATH" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
  echo "docker daemon is not reachable. Start it (this chamber needs a running" >&2
  echo "Docker daemon, a host prerequisite like libvirtd for the vagrant-* chambers)." >&2
  exit 1
}

# A port with nothing accepting connections on 127.0.0.1.
port_free() { ! timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }
pick_port() {
  local p
  for p in "$@"; do port_free "$p" && { echo "$p"; return; }; done
  echo "$1"
}

if [ ! -f .env ]; then
  echo "generating secrets into .env (first run)..."
  minio_pw="$(openssl rand -hex 16)"
  pg_pw="$(openssl rand -hex 16)"
  minio_port="$(pick_port 9090 9190 9290 9390)"
  minio_console_port="$(pick_port 9091 9191 9291 9391)"
  cat > .env <<EOF
MINIO_HOST_PORT=${minio_port}
MINIO_CONSOLE_PORT=${minio_console_port}
POSTGRES_PASSWORD=${pg_pw}
DATABASE_URL=postgresql://postgres:${pg_pw}@postgres:5432/postgres
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
REDIS_AUTH=$(openssl rand -hex 16)
MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=${minio_pw}
ENCRYPTION_KEY=$(openssl rand -hex 32)
SALT=$(openssl rand -hex 16)
NEXTAUTH_SECRET=$(openssl rand -hex 32)
LANGFUSE_INIT_ORG_ID=sanctum
LANGFUSE_INIT_ORG_NAME=Sanctum
LANGFUSE_INIT_PROJECT_ID=local-llm
LANGFUSE_INIT_PROJECT_NAME=local-llm
LANGFUSE_INIT_PROJECT_PUBLIC_KEY=pk-lf-$(openssl rand -hex 16)
LANGFUSE_INIT_PROJECT_SECRET_KEY=sk-lf-$(openssl rand -hex 16)
LANGFUSE_INIT_USER_EMAIL=admin@sanctum.local
LANGFUSE_INIT_USER_NAME=admin
LANGFUSE_INIT_USER_PASSWORD=$(openssl rand -hex 12)
EOF
  chmod 600 .env
else
  echo "reusing existing .env"
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

echo "pulling images and starting the stack..."
docker compose up -d

echo "waiting for langfuse-web to finish migrations and report healthy (up to 180s)..."
ready=""
for _ in $(seq 1 90); do
  if curl -sf --max-time 2 http://localhost:3000/api/public/health >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [ -z "$ready" ]; then
  echo "langfuse-web did not report healthy within 180s. Last web logs:" >&2
  docker compose logs langfuse-web --tail 30 >&2
  exit 1
fi

# shellcheck disable=SC2153
cat <<EOF

Langfuse is up.
  UI:       http://localhost:3000
  Login:    ${LANGFUSE_INIT_USER_EMAIL}  /  ${LANGFUSE_INIT_USER_PASSWORD}
  Project:  ${LANGFUSE_INIT_PROJECT_NAME}
  Keys:     ${LANGFUSE_INIT_PROJECT_PUBLIC_KEY}
            ${LANGFUSE_INIT_PROJECT_SECRET_KEY}
  MinIO:    http://localhost:${MINIO_HOST_PORT} (console http://localhost:${MINIO_CONSOLE_PORT})

Next:  task trace   (send a traced call to the local-llm model)
       task test    (deterministic PASS/FAIL: a trace round-trips the stack)
EOF
