# docker

Container images for Nimbus, built for a small attack surface and non-root, read-only-friendly runtimes.

- `orders-api.Dockerfile` - nimbus-orders-api (Node.js 22 / Express, port 3000)
- `ledger-py.Dockerfile` - nimbus-ledger (Python 3.12 / FastAPI on uvicorn, port 8000)
- `nginx/` - hardened reverse proxy in front of orders-api (ports 8080/8443)

All three build with the **repo root** as context so the Dockerfiles can `COPY` from `app/`.

## Build

```sh
docker build -f docker/orders-api.Dockerfile -t nimbus/orders-api .
docker build -f docker/ledger-py.Dockerfile  -t nimbus/ledger .
docker build -f docker/nginx/Dockerfile       -t nimbus/nginx .
```

## Scan

```sh
trivy image --severity HIGH,CRITICAL --ignore-unfixed nimbus/orders-api
trivy image --severity HIGH,CRITICAL --ignore-unfixed nimbus/ledger
trivy config docker/                              # Dockerfile/misconfig checks
hadolint docker/orders-api.Dockerfile
```

## Hardening choices

- **Multistage builds.** Compilers, dev dependencies, package managers, and the npm/pip
  caches stay in the builder stage and never reach the shipped image. The orders-api runtime
  carries only production `node_modules`; the ledger runtime carries only the resolved venv.
- **Distroless runtime for orders-api** (`gcr.io/distroless/nodejs22-debian12:nonroot`): no
  shell, no package manager, no busybox, so most "drop into the container" and
  living-off-the-land paths are gone. The builder is `node:22-bookworm-slim`, matched to the
  distroless debian12 glibc so native addons and the copied `tini` stay ABI-compatible.
- **Ledger runs on `python:3.12-slim`, not distroless.** Distroless python is version-locked
  to Debian's interpreter (3.11 on debian12), so a 3.12 venv will not run on it, and the
  debian12 language variants are no longer well maintained. We keep 3.12 end to end and drop
  privileges with a dedicated non-root user instead.
- **Non-root.** orders-api runs as uid 65532 (distroless `nonroot`), ledger as a created uid
  10001, nginx as uid 101. nginx binds high ports (8080/8443) and writes its pid and temp
  files under `/tmp`, so nothing needs root and the rootfs can be mounted read-only (mount a
  tmpfs at `/tmp`). Run the app images with `--read-only` plus a tmpfs for any scratch path.
- **Real init (orders-api).** `tini` is installed in the builder and copied into the
  distroless runtime as PID1, so signals are forwarded and zombies reaped. uvicorn handles
  SIGTERM itself, so the ledger runs it directly.
- **Digest pinning.** Base images are pinned by tag here for readability; pin by digest
  (`image@sha256:...`) in CI/prod. Each Dockerfile carries the resolve command
  (`docker buildx imagetools inspect <ref>`).
- **HEALTHCHECK.** orders-api and ledger probe their own `/healthz` over loopback using the
  runtime's own interpreter (no curl/wget in distroless); nginx probes its plain-HTTP
  `/healthz` on 8080 with busybox wget.
- **nginx surface reduction.** `server_tokens off`, TLS 1.2/1.3 only with a modern cipher
  suite, HSTS + `X-Content-Type-Options` + `X-Frame-Options` + `Referrer-Policy` + a tight
  `Content-Security-Policy` for a JSON API, per-IP `limit_req` rate limiting, and request-time
  fields in the access log.

## .dockerignore note

The build context is the repo root, so a `docker/.dockerignore` would be **ignored** by
BuildKit. BuildKit reads `<dockerfile-path>.dockerignore` next to each Dockerfile (falling
back to a `.dockerignore` at the context root). The functional files are therefore
`docker/orders-api.Dockerfile.dockerignore`, `docker/ledger-py.Dockerfile.dockerignore`, and
`docker/nginx/Dockerfile.dockerignore`. They keep `.git`, `node_modules`, `.env*`, tests,
build output, and the other top-level dirs (`terraform/`, `kubernetes/`, ...) out of the
build context.

## Prerequisites from `app/`

- orders-api needs a committed `package-lock.json` (`npm ci` fails without it).
- ledger needs a pinned `requirements.txt`; deps are expected to ship manylinux wheels
  (no build toolchain is installed in the builder).
- Both `/healthz` endpoints must exist for the HEALTHCHECKs to pass.
