# cicd

CI/CD for Nimbus. Three GitHub Actions workflows under
`.github/workflows/`, built around one idea: **shift-left**. Every check runs
at the earliest point it can, so a problem is caught where it is cheapest to
fix (a red PR check) rather than where it is most expensive (a signed image in
prod, or an incident).

Layout mirrors a real repo root. In this repo these live at
`/.github/workflows/`; they are kept under `cicd/` here so the directory reads
as a self-contained study of the pipeline.

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | `pull_request` | Shift-left gates. Nothing ships; findings block the merge. |
| `cd.yml` | push to `main`, tags `v*` | Build, push, sign, deploy dev, DAST, gated prod. |
| `terraform.yml` | PR / push touching `terraform/**` | Plan on PR (commented), apply on merge (gated). |

## Shift-left, and why it is fail-early-and-cheap

The cost of a defect climbs by orders of magnitude the later it is found. A
secret caught by a pre-commit hook costs a `git commit --amend`. The same
secret caught in a PR costs a rotation. In a pushed image it costs a rotation
plus a rebuild plus an incident writeup. So the gates are stacked front to
back: `.pre-commit-config.yaml` at the developer's machine, then `ci.yml` on
every PR running the same tools (a bypassed hook cannot skip the gate), then
`cd.yml` re-scanning the built image before it is signed. Each layer assumes
the one before it can be skipped.

## The gates

### `ci.yml` (pull request)

Top-level `permissions: contents: read`. No CI job writes to the repo, pushes a
package, or touches cloud, so nothing is granted beyond reading the code.
`concurrency` cancels a stale run when a new commit lands on the same PR.

| Gate | Tool | What it catches | Fail condition |
|------|------|-----------------|----------------|
| lint | `terraform fmt` | Unformatted HCL | Any file needs formatting |
| lint | tflint | Provider mistakes, deprecated syntax, bad resource args | Issue at `warning`+ |
| lint | yamllint | Malformed / inconsistent YAML | Any lint error |
| lint | shellcheck | Shell bugs (quoting, unset vars, globbing) | Issue at `warning`+ |
| lint | hadolint | Dockerfile smells (unpinned base, root, `apt` without cleanup) | Issue at `warning`+ |
| sast | semgrep (`p/ci`, `p/owasp-top-ten`) | Insecure code patterns, injection, OWASP Top 10 | Any finding (`--error`) |
| sca + secrets | trivy fs (`vuln,misconfig`) | Vulnerable deps and misconfig in the tree | HIGH/CRITICAL, fixable |
| sca + secrets | gitleaks | Committed secrets, across full history | Any leak |
| iac | checkov | Terraform security misconfig (open SGs, unencrypted storage, public buckets) | Any finding (`soft_fail: false`) |
| iac | trivy config | IaC misconfig, second engine over the same HCL | HIGH/CRITICAL |
| build + scan | trivy image | OS/library CVEs in the built image | HIGH/CRITICAL, fixable |
| build + scan | syft (SBOM) | - (produces the SPDX inventory) | never (artifact only) |

`ignore-unfixed: true` on the trivy vuln/image scans is deliberate: block on
CVEs a base-image or dependency bump can actually fix, and do not wedge the
pipeline on a CVE with no upstream patch. Config and secret scans have no such
exemption.

The image scan runs against a locally-built image that is **loaded, not
pushed**. A PR proves the image is clean before any registry ever sees it.

The deployable workload is upstream `podinfo` (a public, reproducible image
that stands in for the core service), so the build+scan+SBOM steps run once for
a single image rather than across a service matrix. There is no bespoke app
source in the repo, so there is no unit-test job: the pipeline verifies the
image, not application logic.

### `cd.yml` (main / tags)

Top-level `contents: read`. `id-token: write` is granted **per job**, only on
the jobs that assume an AWS role or run cosign. That is the least-privilege
point: the DAST job, which only needs to reach a public URL, never gets an
OIDC token.

| Stage | What it does | Gate |
|-------|-------------|------|
| build-push | Build the image, push to ECR tagged by git SHA | trivy already gated on PR |
| build-push | `cosign sign` keyless, by digest | supply-chain provenance |
| build-push | `cosign attest` the syft SBOM as an spdxjson attestation | supply-chain provenance |
| deploy-dev | `kustomize build overlays/dev \| kubectl apply`, wait for rollout | rollout status |
| dast-dev | OWASP ZAP baseline against the dev endpoint | report-only |
| deploy-prod | Same rollout against prod | **manual approval** (Environment) |

Images are tagged and signed by **git SHA**, and cosign signs the **digest**,
not the tag. A tag can be repointed after signing; a digest cannot. That is
what makes admission-time verification meaningful.

`deploy-prod` sits behind `environment: prod`. The manual approval is not
written in YAML, it is the Environment's required-reviewers rule. GitHub holds
the job until a reviewer approves, which keeps the human gate out of code where
it could be edited in the same PR it is meant to guard.

**Rollback.** `kubectl rollout status --timeout` fails the job if the new
ReplicaSet never becomes Ready, but it does not revert. To roll back:

```
kubectl -n nimbus rollout undo deployment/podinfo
```

Under ArgoCD: `argocd app rollback podinfo-prod <history-id>`, or enable
self-heal so live state is continuously reconciled back to the pinned SHA.

### `terraform.yml` (terraform PRs / merges)

Path-filtered to `terraform/**` so it only runs when infra changes. Matrix over the
Terragrunt env layer `live/{dev,prod}`, driven with `terragrunt run --all`.

| Event | Steps | Gate |
|-------|-------|------|
| pull_request | hcl fmt, hcl validate, checkov, `run --all plan` posted as a PR comment | checkov hard-fails; plan is reviewed |
| push to main | init, `apply -auto-approve` | Environment approval before apply |

`plan` runs under a **read-only** OIDC role (`AWS_TF_PLAN_ROLE_ARN`) and posts
the diff to the PR, so reviewers see exactly what will change before approving.
`apply` runs under a separate **write** role (`AWS_TF_APPLY_ROLE_ARN`) and is
gated on the Environment. Split roles mean a plan can never mutate state, and
`max-parallel: 1` with `[dev, prod]` applies dev before prod.

The plan step is `continue-on-error` on purpose: a failing plan still posts its
diagnostics to the PR, then a follow-up step re-raises the failure so the check
goes red.

Checkov also runs here (per-environment) as well as in `ci.yml` (whole
`terraform/`). That overlap is intentional. `ci.yml` gates every PR; this
workflow only runs on infra PRs but adds the OIDC-backed plan the CI job cannot
produce. Defense in depth, not duplication to remove.

## Fail-closed vs report-only

| Behaviour | Gates |
|-----------|-------|
| **Fail-closed** (blocks merge / ship) | fmt, tflint, yamllint, shellcheck, hadolint, semgrep, trivy fs, gitleaks, checkov, trivy config, trivy image, unit tests, terraform validate |
| **Report-only** (informs, does not block) | syft SBOM (artifact), ZAP baseline (`fail_action: false`) |

ZAP is report-only by design. A baseline (passive) scan against an ephemeral
dev deploy produces false positives that should not wall off the prod approval;
it exists to surface headers, cookie flags, and obvious exposure for triage.
Promote it to blocking once the alert set is tuned, or run a full active scan on
a schedule against a dedicated target.

## Why OIDC, not long-lived AWS keys

The pipeline authenticates to AWS with **GitHub OIDC**. No `AWS_ACCESS_KEY_ID`
or secret key is stored anywhere. `aws-actions/configure-aws-credentials`
exchanges the short-lived GitHub OIDC token for temporary STS credentials
against a role whose trust policy is scoped to this repo (and can be scoped to a
branch, tag, or environment).

- Nothing to leak. There is no static credential in a secret store to exfiltrate
  or forget to rotate.
- Nothing to rotate. Tokens are minted per run and expire in minutes.
- Tightly scoped. The trust policy pins `repo:<org>/<repo>` and a subject
  (branch/tag/environment), so a fork or an unrelated repo cannot assume it.
- Separated by blast radius. Deploy, terraform-plan, and terraform-apply use
  distinct roles, each with only the permissions that stage needs.

The role is provisioned by the `github-oidc` terraform module.

## Supply-chain chain: SBOM, signing, verification

Three links, each meaningless without the others:

1. **SBOM (syft, SPDX-json).** CI produces a per-image component inventory.
   CD regenerates it for the pushed image and attaches it with
   `cosign attest --type spdxjson` as an spdxjson in-toto attestation, signed by
   the same keyless OIDC identity and logged in Rekor. When the next Log4Shell
   lands, you answer "are we affected?" from the SBOM in seconds instead of
   rebuilding to find out.
2. **Signing (cosign, keyless).** CD signs the pushed image **by digest** using
   the same GitHub OIDC identity. The signature and its certificate are logged
   in the public transparency log (Rekor). No long-lived signing key exists to
   steal.
3. **Admission verification.** The cluster refuses to run what it cannot verify.
   Kyverno's `verify-image-signatures` (Enforce) admits only images signed by the
   expected OIDC identity and issuer, and `require-sbom-attestation` (Audit)
   checks the spdxjson attestation is present and signed by the same identity.
   Sign without enforcing verification and the signature is decoration; enforce
   without signing and nothing deploys.

The chain closes the loop: **you build it, you inventory it, you sign it, you
attest it, and the cluster runs only what carries your signature.**

## Required repo configuration

**Branch protection on `main`:**

- Require a PR before merging; require the `ci.yml` checks (lint, sast,
  sca-secrets, iac, build-scan, tests) and, for infra PRs, the terraform `plan`
  checks.
- Require branches up to date before merge.
- Include administrators. Disallow force-push and deletion.

**Environments:**

- `prod` - required reviewers (manual approval), used by `deploy-prod` and the
  prod `terraform apply`. Optionally a wait timer and a branch restriction to
  `main`.
- `dev` - no reviewers (auto-deploy), or a short wait timer if desired.

**Repository variables (`vars`)** - non-secret, so kept as variables:

| Variable | Example |
|----------|---------|
| `AWS_ACCOUNT_ID` | `123456789012` |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789012:role/nimbus-gha-deploy` |
| `AWS_TF_PLAN_ROLE_ARN` | `arn:aws:iam::123456789012:role/nimbus-gha-tf-plan` |
| `AWS_TF_APPLY_ROLE_ARN` | `arn:aws:iam::123456789012:role/nimbus-gha-tf-apply` |
| `DEV_BASE_URL` | `https://dev-api.nimbus.example.com` |

**Secrets:** only `GITLEAKS_LICENSE`, and only if the repo lives under a GitHub
org (gitleaks-action requires it for org-owned repos; personal repos need
nothing). Everything else is OIDC, so there are no cloud credentials to store.

## A note on action pinning

Third-party actions are pinned to a **full commit SHA** with the version in a
trailing comment, so a compromised or retagged upstream release cannot silently
change what runs (the tj-actions/changed-files supply-chain incident is the
reference case). First-party `actions/*` are left on major-version tags for
readability; pinning those to SHA as well is a reasonable hardening step for
higher-assurance repos.

Findings are attached as build artifacts (SARIF, SBOM) to keep the top-level
token read-only. To surface them in the GitHub Security tab instead, grant the
relevant jobs `security-events: write` and upload via
`github/codeql-action/upload-sarif`.
