# podinfo (upstream stefanprodan/podinfo) test workload image.
# Build from repo root: docker build -f docker/podinfo.Dockerfile -t nimbus/podinfo .
#
# No source is vendored: the builder clones a pinned tag and compiles it, so the
# shipped binary is reproducible from a git ref rather than from local files.
#
# Pin base images by digest in prod, e.g.
#   golang:1.26-alpine@sha256:<digest>
#   alpine:3.24@sha256:<digest>
# Resolve with: docker buildx imagetools inspect <ref>

FROM golang:1.26-alpine AS builder

# git is only needed to clone the pinned source; it never reaches the runtime.
# hadolint ignore=DL3018
RUN apk add --no-cache git

WORKDIR /src

ARG PODINFO_VERSION=6.14.1
RUN git clone --depth 1 --branch "${PODINFO_VERSION}" \
      https://github.com/stefanprodan/podinfo.git .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags "-s -w" \
      -o /out/podinfo ./cmd/podinfo


FROM alpine:3.24

# Non-root runtime user; uid/gid match the Kubernetes securityContext (10001).
RUN addgroup -g 10001 -S podinfo \
 && adduser -u 10001 -S -G podinfo podinfo

WORKDIR /home/podinfo

COPY --from=builder /out/podinfo /usr/local/bin/podinfo
# UI is not embedded; the index page needs ui/ (health, metrics and the API do not).
COPY --from=builder --chown=10001:10001 /src/ui ./ui

EXPOSE 9898

USER 10001:10001

# busybox wget ships in alpine, so the probe needs no curl or extra interpreter.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:9898/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/podinfo"]
