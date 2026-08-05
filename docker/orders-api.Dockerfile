# nimbus-orders-api (Node.js 22 / Express) container image.
# Build from repo root: docker build -f docker/orders-api.Dockerfile -t nimbus/orders-api .
#
# Pin base images by digest in prod, e.g.
#   node:22-bookworm-slim@sha256:<digest>
#   gcr.io/distroless/nodejs22-debian12:nonroot@sha256:<digest>
# Resolve with: docker buildx imagetools inspect <ref>   (or: gcrane digest <ref>)
# Builder stays on debian12/bookworm to match the distroless debian12 runtime glibc
# (keeps native addons and the copied tini ABI-compatible).

FROM node:22-bookworm-slim AS builder

WORKDIR /app

# tini gives us a real init as PID1 in the distroless runtime (no package manager there).
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini \
 && rm -rf /var/lib/apt/lists/*

COPY app/orders-api/package.json app/orders-api/package-lock.json ./
RUN npm ci --omit=dev

COPY app/orders-api/ ./


FROM gcr.io/distroless/nodejs22-debian12:nonroot

ENV NODE_ENV=production

WORKDIR /app

COPY --from=builder /usr/bin/tini /usr/bin/tini
COPY --from=builder --chown=65532:65532 /app ./

EXPOSE 3000

USER 65532:65532

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", "require('http').get('http://127.0.0.1:3000/healthz', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]

ENTRYPOINT ["/usr/bin/tini", "--", "/nodejs/bin/node", "src/server.js"]
