# docker

Container images for Nimbus, built for a small attack surface and non-root, read-only-friendly runtimes.

- `podinfo.Dockerfile` - the deployable workload (upstream `stefanprodan/podinfo`, Go, port 9898). A public, reproducible test image stands in for the core service so the platform can be exercised end to end without shipping bespoke app code.
- `nginx/` - hardened reverse proxy in front of podinfo (ports 8080/8443)

Both build with the **repo root** as context. podinfo clones its own source in the builder, so it never `COPY`s from the context; nginx copies its config from `docker/nginx/`.

## Build

```sh
docker build -f docker/podinfo.Dockerfile -t nimbus/podinfo .
docker build -f docker/nginx/Dockerfile    -t nimbus/nginx .
```

## Scan

```sh
trivy image --severity HIGH,CRITICAL --ignore-unfixed nimbus/podinfo
trivy config docker/                              # Dockerfile/misconfig checks
hadolint docker/podinfo.Dockerfile
```

## Hardening choices

- **Multistage build.** The Go toolchain, git, and the cloned source stay in the builder stage and never reach the shipped image. The runtime carries only the statically linked `podinfo` binary (`CGO_ENABLED=0`, `-s -w`) and the `ui/` assets the index page needs.
- **Pinned upstream by git tag.** The builder clones a pinned podinfo tag and compiles it, so the binary is reproducible from a git ref rather than from vendored files. Bumping the version is a one-line `ARG` change.
- **Non-root.** podinfo runs as a created uid/gid 10001 that matches the Kubernetes `securityContext`; nginx runs as uid 101. nginx binds high ports (8080/8443) and writes its pid and temp files under `/tmp`, so nothing needs root and the rootfs can be mounted read-only (mount a tmpfs at `/tmp`). Run the app image with `--read-only`; podinfo needs no writable path in its default configuration.
- **Alpine runtime for podinfo.** `alpine:3.24` keeps the busybox `wget` the HEALTHCHECK uses over loopback, so the probe needs no curl or extra interpreter. Pin the base by digest in CI/prod.
- **HEALTHCHECK.** podinfo probes its own `/healthz` on 9898 with busybox `wget`; nginx probes its plain-HTTP `/healthz` on 8080 the same way.
- **nginx surface reduction.** `server_tokens off`, TLS 1.2/1.3 only with a modern cipher suite, HSTS + `X-Content-Type-Options` + `X-Frame-Options` + `Referrer-Policy` + a tight `Content-Security-Policy` for a JSON API, per-IP `limit_req` rate limiting, and request-time fields in the access log. The upstream targets `podinfo:9898`.
- **Digest pinning.** Base images are pinned by tag here for readability; pin by digest (`image@sha256:...`) in CI/prod. The Dockerfile carries the resolve command (`docker buildx imagetools inspect <ref>`).

## .dockerignore note

The build context is the repo root, so a `docker/.dockerignore` would be **ignored** by BuildKit. BuildKit reads `<dockerfile-path>.dockerignore` next to each Dockerfile (falling back to a `.dockerignore` at the context root). The functional files are therefore `docker/podinfo.Dockerfile.dockerignore` and `docker/nginx/Dockerfile.dockerignore`. They keep `.git`, `node_modules`, `.env*`, and the other top-level dirs (`terraform/`, `kubernetes/`, ...) out of the build context. Because podinfo compiles from a clone rather than the context, its ignore file is purely about keeping the context small and secret-free.
