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
| `terraform/modules/` | Reusable modules: `vpc`, `eks`, `rds`, `cloudflare`, `github-oidc`, and `platform` (the Helm addon layer) |
| `terraform/live/` | Terragrunt env layer: `dev`/`prod` units wiring the modules with S3 + DynamoDB remote state and `dependency`-passed outputs |
| `charts/podinfo/` | Helm chart for the podinfo app: Rollout/Deployment, service, ingress, HPA/PDB, network policies, ServiceMonitor, PrometheusRule, SLO dashboards |
| `kubernetes/` | Cluster + namespace hardening: Pod Security, default-deny NetworkPolicy, RBAC, Kyverno, quotas |
| `gitops/` | ArgoCD `AppProject` + `ApplicationSet` delivering the podinfo chart per environment |
| `security/` | Admission (Kyverno `verifyImages`/cosign), runtime (Falco rules), and posture (kube-bench, Prowler, Trivy) |
| `monitoring/` | Prometheus rules, Grafana dashboards, Alertmanager, multi-burn-rate SLOs |
| `docker/` | Multistage Dockerfile that builds the podinfo workload image from pinned source, and a hardened Nginx reverse proxy |
| `cicd/` | GitHub Actions with shift-left security gates over keyless OIDC |
| `scripts/` | Hardened Bash: health checks, backups, log rotation, EC2 bootstrap |
| `docs/` | Architecture and engineering notes (see below) |

## Infrastructure layer

The modules under `terraform/modules/` are plain Terraform. The `terraform/live/`
Terragrunt layer composes them: each environment is thin config (`env.hcl`) over
identical unit definitions (network, cluster, data, edge, ci, platform), with
`dependency` blocks passing outputs between units. Backend, provider, and wiring are
defined once in `root.hcl`, so adding an environment is a new `env.hcl`, not a copied
root module.

## Platform and delivery

- **Day 1 (platform bootstrap):** `terraform/modules/platform` installs the cluster
  infrastructure via `helm_release` with per-chart IRSA: AWS Load Balancer Controller,
  cert-manager, external-secrets, external-dns, metrics-server, Karpenter,
  kube-prometheus-stack, ArgoCD, Argo Rollouts, Falco, and Kyverno. Each addon is
  toggle-gated.
- **Day 2 (application delivery):** `gitops/` holds the ArgoCD `ApplicationSet` (a list
  generator over environments, the modern replacement for hand-written app-of-apps)
  syncing the `charts/podinfo` Helm chart, whose SLO-gated Argo Rollout canary aborts
  on the Prometheus error budget.

## Security across the lifecycle

Security is not a directory, it runs through all of them: shift-left scanning in CI (SAST,
SCA, secrets, IaC, image, DAST), supply-chain signing (SBOM + cosign) **verified at
admission** by Kyverno, least-privilege runtime (IRSA, Pod Security, default-deny network,
non-root read-only containers), runtime detection (Falco), and posture management
(kube-bench, Prowler, Trivy). See `docs/security-architecture.md` and
`docs/devsecops-shift-left.md`.

## Workloads

`dev` and `prod` deploy a single workload: [podinfo](https://github.com/stefanprodan/podinfo),
the standard cloud-native test app. It exposes health, readiness, and Prometheus metrics,
which is enough to exercise the platform end to end (probes, HPA, scraping, SLOs, canary
rollouts, admission policies). `docker/podinfo.Dockerfile` builds it from pinned upstream
source. It is a test workload, not a real application.

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
