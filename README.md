# Nimbus Platform

A production-grade, best-practices platform blueprint for running secure, self-healing
workloads on **AWS + Kubernetes**. It is built as one coherent system rather than a bag
of snippets: infrastructure as code, a Helm-based platform layer, GitOps delivery,
security controls across the whole lifecycle, observability with SLOs, and CI/CD.

The scope is deliberately broad. It exercises a modern cloud-native stack end to end
(Terraform and Terragrunt, EKS with a full addon layer, ArgoCD with ApplicationSets and
Argo Rollouts, Kyverno and Falco, Prometheus and Grafana, cosign supply-chain signing),
so it doubles as a working reference and a practice ground for the patterns that matter.

Nothing here provisions real infrastructure without your own accounts, state backend, and
secrets. The value is in the shape of the code and the reasoning in `docs/`.

## Layout

| Path | What it holds |
|------|---------------|
| `terraform/modules/` | Reusable plain-Terraform modules: `vpc`, `eks`, `rds`, `serverless-api`, `cloudflare`, `github-oidc`, and `platform` (the Helm addon layer) |
| `terraform/environments/` | Plain-Terraform `dev`/`prod` roots wiring the modules with S3 + DynamoDB remote state |
| `terraform/live/` | Terragrunt orchestration over the same modules (DRY multi-environment layer, `dependency`-wired units) |
| `kubernetes/` | Kustomize base + `dev`/`prod` overlays, and hardening: Pod Security, default-deny NetworkPolicy, RBAC, Kyverno, HPA/PDB |
| `gitops/` | ArgoCD `AppProject` + `ApplicationSet` and an Argo Rollout canary gated on the SLO |
| `security/` | Admission (Kyverno `verifyImages`/cosign), runtime (Falco rules), and posture (kube-bench, Prowler, Trivy) |
| `monitoring/` | Prometheus rules, Grafana dashboards, Alertmanager, multi-burn-rate SLOs |
| `docker/` | Non-root distroless images and a hardened Nginx reverse proxy |
| `cicd/` | GitHub Actions with shift-left security gates over keyless OIDC |
| `app/` | Minimal sample workloads: `orders-api` (Node/Express) and `ledger` (Python/FastAPI) |
| `scripts/` | Hardened Bash: health checks, backups, log rotation, EC2 bootstrap |
| `docs/` | Architecture and engineering notes (see below) |

## Two infrastructure layers, one set of modules

The modules under `terraform/modules/` are plain Terraform. They are consumed two ways:

- **`terraform/environments/`** calls them directly, one root per environment. Simple and
  self-contained, good for a small number of environments.
- **`terraform/live/`** wraps them with Terragrunt: each environment is thin config
  (`env.hcl`) over identical unit definitions, with `dependency` blocks passing outputs
  between units. This is the DRY path that scales to many environments and accounts.

Both are kept so the tradeoff is visible. They use distinct remote-state keys and are not
meant to be applied at the same time.

## Platform and delivery

- **Day 1 (platform bootstrap):** `terraform/modules/platform` installs the cluster
  infrastructure via `helm_release` with per-chart IRSA: AWS Load Balancer Controller,
  cert-manager, external-secrets, external-dns, metrics-server, Karpenter,
  kube-prometheus-stack, ArgoCD, Falco, and Kyverno. Each addon is toggle-gated.
- **Day 2 (application delivery):** `gitops/` holds the ArgoCD `ApplicationSet` (a git
  directory generator over the overlays, the modern replacement for hand-written
  app-of-apps) and an Argo Rollout whose canary aborts on the Prometheus SLO error budget.

## Security across the lifecycle

Security is not a directory, it runs through all of them: shift-left scanning in CI (SAST,
SCA, secrets, IaC, image, DAST), supply-chain signing (SBOM + cosign) **verified at
admission** by Kyverno, least-privilege runtime (IRSA, Pod Security, default-deny network,
non-root read-only containers), runtime detection (Falco), and posture management
(kube-bench, Prowler, Trivy). See `docs/security-architecture.md` and
`docs/devsecops-shift-left.md`.

## Workloads

`dev` and `prod` deploy only the two minimal sample services in `app/` as their workloads:
`orders-api` on the cluster, `ledger` as the serverless path. They exist to exercise the
platform (health, readiness, metrics, rollouts, policies), not to be a real application.

## Toolchain

A Nix flake pins the full toolchain (`flake.lock`), so every tool version is reproducible:

```sh
nix develop   # terraform, terragrunt, kubectl, kustomize, hadolint, trivy, cosign, gitleaks, promtool, ...
```

## Docs

- `docs/00-scenario.md` - the platform, architecture diagram, and naming conventions
- `docs/well-architected.md`, `resilience-auto-recovery.md`, `networking-fundamentals.md` - engineering notes
- `docs/devsecops-shift-left.md`, `security-architecture.md` - the security model
- `docs/gitops.md` - the GitOps and progressive-delivery design
- `docs/interview-cheatsheet.md` - personal notes, kept out of the platform narrative
