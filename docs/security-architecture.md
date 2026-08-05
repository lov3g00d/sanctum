# Security architecture

The threat model, controls matrix, compliance mapping, and incident-response
outline for Nimbus. It ties the abstract question ("is this secure?") to
concrete files in this repo: every control named here points at the manifest,
workflow, or policy that implements it, and states whether that control is
enforced, audit-only, or aspirational today.

Nimbus is a B2B API platform (see [`00-scenario.md`](00-scenario.md)). Partners
integrate against `api.nimbus.example.com`, so a compromise is not an internal
inconvenience, it is visible to paying customers and their data. That framing
sets the priorities below: protect partner data and platform integrity, and keep
the blast radius of any single compromise small.

## Trust boundaries and attack surface

The request path in `00-scenario.md` is also the attack surface. Each arrow
crossing a boundary is where an attacker's assumptions change and where a
control belongs.

| # | Boundary | Crossing | Primary threat |
|---|----------|----------|----------------|
| B1 | Internet to edge | Partner/attacker to Cloudflare | Volumetric DDoS, app-layer attacks, bot/credential stuffing |
| B2 | Edge to AWS | Cloudflare to ALB | Origin bypass (hitting the ALB directly), WAF evasion |
| B3 | Ingress to workload | ALB to EKS pod | Injection, auth bypass, SSRF into the VPC |
| B4 | Pod to data | podinfo to RDS / Redis / S3 | Lateral movement, data exfil, over-broad DB grants |
| B5 | Supply chain to cluster | CI to ECR to admission | Tampered or unsigned image, malicious dependency |
| B6 | Operator to control plane | Human/CI to AWS API and K8s API | Credential theft, privilege escalation, config drift |

The workload runs on EKS behind the edge. B1 and B2 are the shared edge
boundaries; B3 is where a request enters the cluster, carrying its own network
and pod-security controls.

## STRIDE threat model

STRIDE per boundary, with the control that addresses each threat and its
location. "Residual" is what remains after the control and is handled by
detection or accepted.

### B1/B2 edge

| Threat | Vector | Control | Where |
|--------|--------|---------|-------|
| Denial of service | Volumetric / L7 flood | Cloudflare DDoS + rate limiting; HPA/Karpenter absorb legitimate spikes | `terraform/modules/cloudflare/`, `kubernetes/base/hpa.yaml` |
| Tampering | Origin bypass to hit ALB directly | Authenticated origin pull (mTLS) edge to ALB; WAFv2 on the ALB | scenario B2, ALB ingress `kubernetes/base/ingress.yaml` |
| Info disclosure | TLS downgrade / sniffing | TLS at edge and re-terminated at ALB (ACM) | edge, ingress |

### B3 ingress to workload

| Threat | Vector | Control | Where |
|--------|--------|---------|-------|
| Tampering / EoP | Injection, insecure deserialization | semgrep SAST fail-closed on PR | `cicd/ci.yml` |
| Spoofing | Weak/absent authn on endpoints | App-layer auth; edge WAF; DAST baseline surfaces gaps | `cicd/cd.yml` (ZAP) |
| Info disclosure | Verbose errors, missing headers | DAST baseline flags headers/cookies for triage | `cicd/cd.yml` |
| EoP | SSRF pivoting into the VPC | Default-deny egress NetworkPolicy limits where a pod can reach | `kubernetes/security/networkpolicy.yaml` |

### B4 pod to data

| Threat | Vector | Control | Where |
|--------|--------|---------|-------|
| Lateral movement | Compromised pod scanning the namespace | Default-deny ingress/egress, explicit allows only to RDS/Redis CIDR | `kubernetes/security/networkpolicy.yaml` |
| EoP | Pod reading other secrets via API | RBAC scoped by `resourceNames` to the workload's own ConfigMap/Secret | `kubernetes/security/rbac.yaml` |
| Info disclosure | Credential theft from the pod | IRSA short-lived creds, not node role; secrets from Secrets Manager, never in Git | `kubernetes/base/serviceaccount.yaml`, `kubernetes/README.md` |
| Spoofing | Stolen SA token used against the API server | Falco alerts on token read by a shell | `security/falco/custom-rules.yaml` |
| Repudiation | Post-compromise persistence/tampering | Read-only rootfs; Falco alerts on writes to sensitive dirs and shell spawn | PSA restricted + `security/falco/custom-rules.yaml` |

### B5 supply chain

| Threat | Vector | Control | Where |
|--------|--------|---------|-------|
| Tampering | Malicious image pushed to ECR | Kyverno `verify-images` admits only images signed by the CI OIDC identity (Enforce) | `security/kyverno/verify-images.yaml` |
| Tampering | Vulnerable dependency shipped | trivy fs + image scans fail-closed on HIGH/CRITICAL fixable | `cicd/ci.yml` |
| Repudiation | "Which images have package X?" unanswerable | syft SBOM per image | `cicd/ci.yml` |
| Provenance gap | No verifiable bill of materials at admission | SBOM attestation policy (Audit, aspirational; needs `cosign attest` in CI) | `security/kyverno/require-signed-and-sbom.yaml` |

### B6 control plane

| Threat | Vector | Control | Where |
|--------|--------|---------|-------|
| Spoofing | Leaked long-lived AWS keys | GitHub OIDC, no static keys; trust scoped to repo + ref | `cicd/README.md`, `terraform/modules/github-oidc/` |
| EoP | CI role too broad | Split roles per stage (deploy / tf-plan / tf-apply), least privilege | `cicd/cd.yml`, `terraform/` |
| Tampering | Manual console change bypassing IaC | Prowler CSPM catches account drift; kube-bench catches cluster drift | `security/cspm/` |
| Repudiation | No record of who changed what | CloudTrail + branch protection + reviewed PRs | scenario, `cicd/README.md` |

## Controls matrix

Every control, where it is implemented, what it mitigates, and its enforcement
state. State matters: an audit-only or aspirational control informs but does not
block, and the matrix is honest about which is which.

| Control | Implemented in | Mitigates | State |
|---------|----------------|-----------|-------|
| Secret detection | `.pre-commit-config.yaml`, `cicd/ci.yml` (gitleaks) | Leaked credentials | Enforced (CI) |
| SAST | `cicd/ci.yml` (semgrep) | Injection, insecure code | Enforced |
| SCA / dependency CVE | `cicd/ci.yml` (trivy fs) | Vulnerable dependencies | Enforced (HIGH/CRITICAL fixable) |
| IaC misconfig | `.pre-commit-config.yaml`, `cicd/` (checkov, trivy config) | Open SG, public bucket, unencrypted store | Enforced |
| Image CVE (build) | `cicd/ci.yml` (trivy image) | Vulnerable OS/runtime packages | Enforced |
| SBOM | `cicd/` (syft) | Unanswerable CVE exposure questions | Produced (artifact) |
| Image signing | `cicd/cd.yml` (cosign keyless) | Tampered artifact | Enforced (signs by digest) |
| Signature verification | `security/kyverno/verify-images.yaml` | Unsigned/foreign image scheduled | **Enforce** |
| SBOM attestation | `security/kyverno/require-signed-and-sbom.yaml` | No verifiable BOM at admission | **Audit (aspirational)** |
| Pod Security Admission | `kubernetes/security/namespace.yaml` | Privileged/root/host-mount pods | Enforced (`restricted`) |
| Pod hardening policies | `kubernetes/security/kyverno-policies.yaml` | `:latest`, root, writable rootfs, no limits, extra caps | Enforced |
| Network segmentation | `kubernetes/security/networkpolicy.yaml` | Lateral movement, unexpected egress | Enforced (default-deny) |
| Least-privilege RBAC | `kubernetes/security/rbac.yaml` | Token enumerating other secrets | Enforced (namespaced, by name) |
| Workload identity | `kubernetes/base/serviceaccount.yaml` (IRSA) | Node-wide credential blast radius | Enforced |
| Runtime detection | `security/falco/custom-rules.yaml` | Shell, exfil, tampering, token theft | Detect (alert) |
| DAST | `cicd/cd.yml` (ZAP baseline) | Runtime exposure static analysis misses | Report-only |
| Cluster CIS audit | `security/cspm/kube-bench-job.yaml` | Node/cluster misconfig vs CIS EKS | Audit (on demand) |
| Continuous cluster posture | `security/cspm/trivy-operator.md` | Running-image CVE, config/RBAC drift | Detect (continuous) |
| AWS CSPM | `security/cspm/prowler-cronjob.yaml` | Account drift vs CIS AWS Foundations | Audit (weekly) |
| Edge protection | `terraform/modules/cloudflare/` | DDoS, L7 attacks, bots | Enforced |

## CIS and compliance mapping

### CIS Kubernetes / EKS Benchmark

| CIS area | Repo control |
|----------|--------------|
| 4.x worker node config | kube-bench `node` target (`security/cspm/kube-bench-job.yaml`) |
| 5.1 RBAC and service accounts | `kubernetes/security/rbac.yaml`, scoped SA |
| 5.2 Pod Security Standards | PSA `restricted` (`kubernetes/security/namespace.yaml`) + Kyverno pod-hardening policies |
| 5.3 Network policies | `kubernetes/security/networkpolicy.yaml` default-deny |
| 5.7 general policies | Kyverno `verify-images`, disallow-latest, resource limits |
| Continuous scoring | Trivy Operator `ClusterComplianceReport` (`k8s-cis`) |

### CIS AWS Foundations Benchmark

Covered by Prowler (`security/cspm/prowler-cronjob.yaml`, `--compliance
cis_3.0_aws`), reinforced by IaC scanning in CI:

| CIS AWS area | Repo control |
|--------------|--------------|
| 1.x IAM | GitHub OIDC + split least-privilege roles; Prowler flags drift |
| 2.x storage/logging | checkov/trivy config on Terraform (encryption, public access, CloudTrail) |
| 3.x logging/monitoring | CloudTrail, VPC Flow Logs, GuardDuty (scenario Stage 4) |
| 4.x networking | Security groups and NACLs in `terraform/modules/vpc/`; Prowler checks exposure |

### SOC2 and PCI relevance

Nimbus is not claiming certification here; this maps the controls to the trust
criteria a B2B partner's security review will ask about.

| Framework | Criterion | Repo evidence |
|-----------|-----------|---------------|
| SOC2 | CC6 logical access | RBAC, IRSA, OIDC, NetworkPolicy, PSA |
| SOC2 | CC7 system operations / monitoring | Falco, Prowler, kube-bench, `monitoring/`, GuardDuty |
| SOC2 | CC8 change management | Branch protection, reviewed PRs, signed images, IaC |
| PCI DSS | Req 1/2 network and config | NetworkPolicy, security groups, PSA `restricted` |
| PCI DSS | Req 6 secure SDLC | SAST/SCA/secret/IaC gates, signing, verification |
| PCI DSS | Req 10 logging | CloudTrail, Falco events, VPC Flow Logs |
| PCI DSS | Req 11 security testing | DAST, kube-bench, Prowler, trivy |

The recurring point: the same controls satisfy multiple frameworks. NetworkPolicy
is CIS Kubernetes 5.3, SOC2 CC6, and PCI Req 1 at once. Build the control, map it
many ways, do not build one per framework.

## Incident response outline

Scoped to the compromises this platform is most exposed to: a compromised pod,
a malicious image, and leaked cloud credentials. It assumes the detection layer
(Falco, GuardDuty, DAST, CloudWatch alarms) is what raises the first signal.

### 1. Detect and triage

- **Signal sources.** Falco rule fires (shell in container, token read, off-cluster egress), GuardDuty finding, Prowler/kube-bench drift, or an SLO/error alert from `monitoring/`.
- **Triage.** Confirm scope from the Falco/GuardDuty output fields: which namespace, pod, image, principal. Decide compromise class (pod, image, or credential) because containment differs.

### 2. Contain

- **Compromised pod.** Isolate before killing, so forensics survive: apply a deny-all NetworkPolicy selecting the pod, or cordon the node. Then capture, then delete. Kubernetes reschedules a clean replica from the signed image.
- **Malicious image.** `verify-images` should already have blocked an unsigned image; if a signed-but-bad image shipped, revoke by removing the tag, and roll back: `kubectl -n nimbus rollout undo deployment/podinfo` (see `cicd/README.md`).
- **Leaked credential.** IRSA and OIDC creds are short-lived, which shrinks the window. Revoke the IAM role session / rotate the affected secret in Secrets Manager, and tighten the OIDC trust subject if the CI identity is implicated.

### 3. Eradicate and recover

- Identify root cause: the dependency, the misconfig, or the exposed endpoint. Fix at source (dependency bump, policy tightening, IaC change) so the fix ships through the same gated pipeline.
- Rebuild and redeploy the signed image. Confirm the replacement is admitted by `verify-images` and passes readiness before shifting traffic back.
- Rotate anything the attacker could have touched, on the assumption they did.

### 4. Post-incident

- Timeline from CloudTrail, Falco events, and VPC Flow Logs. Repudiation controls (audit logging, reviewed PRs) are what make this reconstruction possible.
- Turn the gap into a control: a new Falco rule, a promoted Kyverno policy (Audit to Enforce), a checkov custom check, or a tightened NetworkPolicy. The incident that produced no durable control was half wasted.
- Feed the finding back to the earliest layer that could have caught it. A CVE that reached runtime should have failed a CI gate; a drifted resource should have failed a Prowler check. Left is always cheaper than right.
