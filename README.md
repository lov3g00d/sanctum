# Nimbus: DevSecOps reference platform

A single, coherent reference implementation of a secure, self-healing B2B platform on
**AWS + Cloudflare**, built to map one-to-one against a Senior DevSecOps role: IaC,
CI/CD with security gates, Kubernetes + serverless compute, observability, and
automatic failure recovery.

It is a *study and reference* repo, not a deployable production system. Nothing here
provisions real infrastructure without your own accounts, state backend, and secrets.
The value is in the shape of the code and the reasoning in the docs.

## Start here

1. [`docs/00-scenario.md`](docs/00-scenario.md): the platform, the architecture diagram, and the fixed conventions every directory follows.
2. [`docs/interview-cheatsheet.md`](docs/interview-cheatsheet.md): rapid-fire Q&A per topic. Read this last, the night before.

## Layout

| Path | What it shows |
|------|---------------|
| `terraform/` | AWS + Cloudflare IaC: reusable modules, `dev`/`prod` envs, remote state, security scanning |
| `kubernetes/` | Kustomize manifests + hardening: NetworkPolicy, Pod Security, RBAC, HPA/PDB, Kyverno policies |
| `docker/` | Multistage, non-root, distroless images + hardened Nginx reverse proxy |
| `cicd/` | GitHub Actions with shift-left security gates (SAST, SCA, secret/IaC/image scan, SBOM, signing, DAST) |
| `monitoring/` | Prometheus rules, Grafana dashboards, Alertmanager routing, SLOs and error budgets |
| `scripts/` | Hardened Bash: health checks, backups, log rotation, EC2 user-data |
| `app/` | Minimal Node.js/Express and Python/FastAPI services with health, readiness, and metrics endpoints |
| `docs/` | Well-Architected mapping, DevSecOps SDLC, networking fundamentals, resilience, interview prep |

## Toolchain

The repo ships a Nix flake with the full toolchain pinned (`flake.lock`), so every
tool version is reproducible:

```sh
nix develop            # terraform, kubectl, hadolint, checkov, trivy, gitleaks, semgrep, ...
```

If you do not use Nix, install the tools listed in `flake.nix` `packages` yourself.

## The DevSecOps thread

Security is not a directory here; it runs through all of them. The controls, and where
each one lives, are laid out in [`docs/devsecops-shift-left.md`](docs/devsecops-shift-left.md).
The short version:

- **Shift left**: scanning happens in pre-commit and CI, before merge: SAST, dependency
  (SCA), secrets, IaC misconfig, container CVEs, and DAST against a running instance.
- **Supply chain**: images are built reproducibly, an SBOM is generated, and images are
  signed with cosign; deploys can require a valid signature.
- **Least privilege at runtime**: OIDC federation instead of long-lived cloud keys,
  IRSA per workload, network policies default-deny, non-root read-only containers,
  secrets from AWS Secrets Manager / SSM, never in Git.
