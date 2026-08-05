# security

The runtime and posture half of Nimbus DevSecOps. `cicd/` and
`docs/devsecops-shift-left.md` cover the shift-left half (scan in pre-commit and
CI, sign the artifact). This directory picks up where the pipeline ends: it
verifies the signature at admission, enforces policy on what runs, detects what
policy could not prevent, and audits the account and cluster for drift.

The Kyverno and Falco **engines** are installed by the platform (Helm). This
directory ships the **policies, rules, and jobs** those engines run, plus the
CSPM scanners and the architecture doc. Nothing here modifies `kubernetes/`,
`cicd/`, or `terraform/`; it composes with them.

## The layered control map

Each layer assumes the one before it can fail. Read left to right as an image's
lifecycle from commit to running pod to audited account.

| Layer | Runs where | Controls | Lives in |
|-------|-----------|----------|----------|
| Shift-left | Pre-commit, CI | SAST, SCA, secrets, IaC, image CVE, SBOM | `.pre-commit-config.yaml`, `cicd/` |
| Supply chain | CI build/release | cosign keyless signing by digest | `cicd/cd.yml` |
| Admission | API server | Verify signature; PSA restricted; policy-as-code | `security/kyverno/`, `kubernetes/security/` |
| Runtime | Node (eBPF/syscalls) | Detect shell, exfil, tampering, token theft | `security/falco/` |
| Posture | Scheduled in-cluster + account | CIS Kubernetes, CIS AWS, drift, running-image CVE | `security/cspm/` |

The admission and runtime layers already have preventive controls in
`kubernetes/security/` (PSA `restricted`, default-deny NetworkPolicy,
least-privilege RBAC, the five Kyverno validation policies). This directory adds
the two pieces those cannot cover on their own: signature verification (closing
the CI signing loop) and runtime detection (the residual-risk layer).

## What each file does

### `kyverno/`

| File | Kind | Mode | Purpose |
|------|------|------|---------|
| `verify-images.yaml` | ClusterPolicy | **Enforce** | Admit only nimbus ECR images carrying a valid cosign signature from the `cd.yml` OIDC identity. Closes the loop with the CI signing step. |
| `require-signed-and-sbom.yaml` | ClusterPolicy | **Audit (aspirational)** | Require an SPDX SBOM attestation on the image. The pipeline does not attach one yet; see the header for the `cosign attest` step this needs. |

Both depend on the Kyverno admission-controller ServiceAccount having ECR read
(IRSA), or admission fails closed and nothing schedules. This is the single most
common way these policies break in practice.

### `falco/custom-rules.yaml`

Runtime rules loaded alongside Falco's default set: shell spawned in a
container, package manager run at runtime, write to a sensitive directory,
service-account token read by a shell, unexpected off-cluster egress. Built on
Falco's shipped macros and lists; namespace scoping needs the `k8smeta` plugin.

### `cspm/`

| File | Runs | Scope |
|------|------|-------|
| `kube-bench-job.yaml` | Job in `kube-system` | CIS EKS Benchmark v1.8.0 against worker nodes |
| `prowler-cronjob.yaml` | Weekly CronJob in `security` | CIS AWS Foundations against the account (IRSA, read-only) |
| `trivy-operator.md` | Continuous, in-cluster | Running-image CVEs, config audit, cluster CIS compliance |

kube-bench needs host access so it runs in `kube-system` (unrestricted); Prowler
is read-only so it runs policy-clean in a restricted namespace. That contrast is
the point: a control lands wherever its privilege requirement lets it.

## Rolling a policy from Audit to Enforce

Every Kyverno policy here and in `kubernetes/security/` sets its action per rule
(`failureAction`), so promotion is a one-line change reviewed like any other.

1. **Ship Audit.** Set `failureAction: Audit`. The policy evaluates every
   admission and records the verdict without blocking.
2. **Watch the reports.** `kubectl get policyreport -A` and
   `clusterpolicyreport`. A rule in Audit that would block a legitimate workload
   shows up here before it can cause an outage.
3. **Fix the fallout, not the policy.** A `fail` in the report is usually a
   workload to correct (an unsigned sidecar, a missing limit), not a policy to
   loosen. Loosen only for a deliberate, documented exception.
4. **Promote.** Flip to `failureAction: Enforce`. From here the API server
   rejects the violating resource at admission.

`verify-images.yaml` ships Enforce because signature verification is the whole
point of the CI signing step; the header still calls out running it Audit first
on an existing cluster. `require-signed-and-sbom.yaml` stays Audit until the
pipeline attaches the SBOM attestation it checks for.

## Apply order

```sh
# Admission policies (engines already installed by the platform)
kubectl apply -f security/kyverno/

# Runtime rules are mounted into the Falco DaemonSet by the platform;
# reference security/falco/custom-rules.yaml as the custom rules file.

# Posture scanners
kubectl apply -f security/cspm/kube-bench-job.yaml
kubectl apply -f security/cspm/prowler-cronjob.yaml
```

See `docs/security-architecture.md` for the threat model, the full controls
matrix, the CIS and compliance mapping, and the incident-response outline.
