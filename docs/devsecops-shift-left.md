# DevSecOps: security across the SDLC

DevSecOps is not a scanner you bolt on at the end. It is moving every security
control as early (left) in the lifecycle as it can run, so defects are caught when
they are cheap, and making the controls automatic so they do not depend on someone
remembering. The economics are the whole argument: a misconfig caught in pre-commit
costs seconds, the same misconfig caught in production costs an incident.

The controls below are ordered by how early they run. Every one of them exists
somewhere in this repo.

## Stage 0 - developer workstation (pre-commit)

`.pre-commit-config.yaml` at the repo root. Runs on `git commit`, before anything
leaves the laptop.

| Control | Tool | Catches |
|---------|------|---------|
| Secret detection | gitleaks | AWS keys, tokens, private keys about to be committed |
| Terraform hygiene | terraform_fmt, terraform_validate | malformed / drifting IaC |
| IaC misconfig | checkov | public S3, open SG, unencrypted volume |
| Shell correctness | shellcheck | quoting bugs, unset-var footguns |
| Dockerfile lint | hadolint | root user, unpinned base, apt cache bloat |
| Block main commits | no-commit-to-branch | direct pushes bypassing review |

Pre-commit is advisory (a developer can `--no-verify`), so the same checks run again
in CI where they are mandatory. Defense in depth: the hook is for speed, the pipeline
is for enforcement.

## Stage 1 - pull request (CI, fail-closed)

`cicd/.github/workflows/ci.yml`. Nothing merges if a gate fails above threshold.

| Gate | Tool | What it catches | Fails on |
|------|------|-----------------|----------|
| SAST | semgrep | injection, unsafe deserialization, auth bugs in source | rule match |
| SCA | trivy fs | known CVEs in dependencies | HIGH/CRITICAL |
| Secrets | gitleaks | leaked credentials in history | any finding |
| IaC | checkov, trivy config | cloud misconfiguration | policy violation |
| Image CVEs | trivy image | vulnerable OS/runtime packages in the built image | HIGH/CRITICAL |
| SBOM | syft | produces the bill of materials (spdx-json) | n/a, artifact |

The distinction to state clearly: **SAST reads your source, SCA reads your
dependencies, image scanning reads the assembled container.** They overlap little
and you need all three.

## Stage 2 - build and release (supply chain)

`cicd/.github/workflows/cd.yml`. The threat here is a tampered artifact, not a bug in
your code.

- **SBOM** with syft: you cannot respond to the next Log4Shell in hours if you do not already know which images contain the package. The SBOM is the inventory.
- **Signing** with cosign (keyless, OIDC-backed): the image is signed at build so its provenance is verifiable.
- **Admission verification**: the cluster can be configured (Kyverno `verifyImages` or sigstore policy-controller) to reject any image without a valid signature from your CI identity. That closes the loop, an attacker who pushes a malicious image to ECR cannot get it scheduled.
- This is the SLSA framework's concern: provenance and integrity of the build pipeline itself.

## Stage 3 - deploy-time (policy as code)

`terraform/modules/platform/policies/` (cluster posture and Kyverno policies,
delivered by the platform module).

- **Pod Security Admission** set to `restricted` on the namespace: the API server rejects privileged pods, host mounts, and root containers at admission.
- **Kyverno ClusterPolicies**: disallow `:latest`, require non-root, require read-only rootfs, require resource limits, require dropped capabilities. Policy as code, versioned and reviewed like everything else.
- **RBAC** least-privilege and **default-deny NetworkPolicy** so a compromised pod has no lateral movement and no unexpected egress.

## Stage 4 - runtime (detect what you could not prevent)

- **Falco** (or the managed equivalent) for runtime threat detection: alerts on a shell spawned in a container, unexpected outbound connection, sensitive file read. Prevention is never complete, so you also detect.
- **Cloudflare WAF + rate limiting** at the edge, and **GuardDuty / VPC Flow Logs** on the AWS side for anomalous network and API activity.
- **CSPM**: Prowler / ScoutSuite periodically against the account to catch drift from the secure baseline that IaC alone cannot see (someone's manual console change).

## Stage 5 - continuous (posture and response)

- **DAST**: OWASP ZAP baseline in `cd.yml` against the running dev environment, exercising the app the way an attacker would, catching what static analysis cannot.
- **CIS benchmarking**: kube-bench against the cluster, CIS AWS Foundations via the scanners above.
- **Patch cadence**: dependency PRs (Renovate/Dependabot) keep the SBOM moving, so CVE exposure windows stay short.

## The one-paragraph answer to "what is DevSecOps to you"

> "Security controls that run automatically as early in the lifecycle as they can,
> so problems are cheap to fix and nothing depends on human memory. Concretely: scan
> in pre-commit and CI (SAST, SCA, secrets, IaC, images), prove the supply chain with
> SBOMs and signed artifacts verified at admission, enforce least privilege at runtime
> with policy-as-code and network policy, and detect the residue with runtime security
> and DAST. Every gate fails closed, and every control is version-controlled and
> reviewed like application code."
