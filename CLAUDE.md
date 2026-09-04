# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Sanctum is a collection of **chambers**: self-contained infrastructure labs, each an
environment you stand up and tear down on its own. It is built for practice and prototyping,
not shipped as a product. Chambers are independent and additive: a new lab is a new
`chambers/<name>/` directory and nothing else moves. `shared/` holds the pieces the
Kubernetes chambers reference instead of copying (the `podinfo` Helm chart, the ArgoCD
GitOps layer, Docker images, red-team fixtures).

## Toolchain

Every tool is pinned in the Nix flake. Enter the dev shell before doing anything:

```sh
nix develop        # or `direnv allow` once, then it loads automatically via .envrc
```

The shell provides terraform, terragrunt, tflint, kubectl, helm, kustomize, kind, kcat,
`go-task`, vagrant, ansible (with pywinrm baked into its own closure for WinRM), the
security tooling (trivy, checkov, semgrep, gitleaks, cosign, syft, grype, hadolint),
observability CLIs (promtool, amtool, logcli), and app runtimes (python312, nodejs_22,
ollama, uv). Do not assume a tool is on the host; if it is missing, it belongs in `flake.nix`.

## Running a chamber

Each chamber except `aws-eks` is driven by a `Taskfile.yml` (`go-task`). The standard
lifecycle is `task up` to stand up and `task down` to tear down; `task` with no argument
lists that chamber's tasks. Run tasks from inside the chamber directory:

```sh
cd chambers/kind-kafka && task up          # kind + Strimzi + Kafka
task smoke                                  # per-chamber demos: smoke, ha, tls, cdc, ...
task down                                    # delete the kind cluster
```

Chamber-specific notes:
- **kind-\*** chambers each own their kind cluster (named `sanctum-<thing>`) and are safe to
  run in parallel. `task down` deletes the whole cluster, so it is a clean reset.
- **vagrant-\*** chambers bring up libvirt VMs (`task up` wraps `vagrant up` + Ansible).
  libvirtd is a host prerequisite, not something Nix provides.
- **local-sre-copilot** is a `uv`-managed Python project (`app/`, `pyproject.toml`, `uv.lock`).
  `task up` runs `scripts/up.sh` (Ollama + models + ingest + MCP server + API); ask it a
  question with `task ask -- "..."`. Run Python via `uv run`, never a bare `python`.
- **aws-eks** has no Taskfile; it is provisioned with Terragrunt (see below) and costs real
  money. Treat any `terragrunt apply`/`destroy` as a mutation that needs explicit confirmation.

## aws-eks: Terraform + Terragrunt

Reusable modules in `terraform/modules/` are composed by a Terragrunt `live/` env layer.
Each `live/<env>/eu-central-1/<unit>/terragrunt.hcl` is a thin pointer at one module; units
(`network`, `cluster`, `data`, `edge`, `ci`, `platform`) pass outputs to each other via
`dependency` blocks and apply bottom-up by dependency. Backend (S3 with native `use_lockfile`
locking) and the AWS provider are generated once in `live/root.hcl`; environment differences
live only in `env.hcl` (account id, region, ha flag). Do not duplicate backend/provider config
into a unit.

```sh
cd chambers/aws-eks/terraform/live/dev/eu-central-1
terragrunt run-all apply       # or per unit, network -> cluster -> platform
terragrunt run-all destroy     # reverse order; remove LB-backed workloads first
```

The `platform` module is the day-1 bootstrap: it installs the Helm addon layer (Cilium,
ArgoCD, kube-prometheus-stack, cert-manager, Karpenter, Kyverno/Falco/Trivy) *and* all
cluster-wide config. Two module styles coexist on purpose: `vpc/` is hand-written raw
`aws_*` resources (teachable), `eks/` wraps `terraform-aws-modules/eks` at an exact pin.

## Validation and CI

There is no unit-test suite. Correctness is shown two ways: a chamber's own demo tasks
(e.g. `task ha`, `task tls`, `task alerts`), and a shift-left security gate that runs the
same tools at three stages.

- **pre-commit** (`.pre-commit-config.yaml`): install once with `pre-commit install` inside
  the dev shell. Runs terraform fmt/validate/checkov, shellcheck, hadolint, gitleaks. Blocks
  commits to `main`.
- **GitHub Actions**: `ci.yml` (fmt, tflint, yamllint, shellcheck, hadolint, semgrep, trivy
  fs, gitleaks, checkov, trivy config, image build + scan + SBOM) on PRs; `cd.yml` (build,
  push, cosign keyless sign, deploy) on push to `main`; `terraform.yml` (plan + cost) and
  `redteam.yml`. Workflows are read-only by default with per-job least-privilege grants, and
  every action is pinned to a commit SHA. Keep both when editing.

Reproduce a CI failure locally before pushing: the exact commands live in `ci.yml`
(`terraform fmt -check -recursive chambers/aws-eks/terraform/`, `tflint --recursive`,
`yamllint -c .yamllint .`, `shellcheck`, etc.).

## Conventions worth knowing

- **Bash**: standalone scripts own `set -euo pipefail` and their own traps. `scripts/lib/common.sh`
  is a *sourced* library and deliberately sets neither, so it never mutates the caller's shell.
  Reuse its `log`/`die`/`require_cmd`/`retry_with_backoff` helpers rather than reinventing them.
- **Prefer the format's own tool**: `jq` for JSON, `yq` for YAML, `promtool`/`amtool` for
  Prometheus rules.
- **`shared/redteam/`** holds *deliberately insecure* attack fixtures (privileged pods, hostPath
  mounts, unsigned images). They are excluded from the CI misconfig gates on purpose. Never
  "fix" them, and never let a new scan pick them up. `run-validation.sh` is authorized
  purple-team self-validation against a cluster you own; it applies each attack and asserts a
  control (PSA/Kyverno admission-deny or Tetragon runtime-kill) blocked it.
- **Docs** live in `docs/` (architecture, networking, observability, security model, GitOps).
  Start with `docs/00-scenario.md` for the reference scenario and naming conventions.
- Each chamber has its own `README.md` and a longer `<name>.md` writeup; read them before
  changing a chamber's mechanics.
