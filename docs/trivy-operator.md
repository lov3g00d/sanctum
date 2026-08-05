# Trivy Operator: in-cluster posture

CI (`.github/workflows/ci.yml`) scans images once, at build time, against the CVE database of
that day. That snapshot goes stale: a new CVE published after the image ships is
invisible until the next rebuild. Trivy Operator closes that gap by scanning
what is actually running, continuously, from inside the cluster, and by
re-scanning as the vulnerability database updates.

It is the running-cluster counterpart to the shift-left image scan, not a
replacement. CI blocks a bad image from ever being built; the operator catches
the image that was clean when built and became vulnerable in place.

## Deployment

Deployed by the platform module, `chambers/aws-eks/terraform/modules/platform/trivy-operator.tf`,
into the `trivy-system` namespace and gated by `enable_trivy_operator`. The chart
version is pinned in `variables.tf` and bumped as a reviewed change, the same
discipline applied to the kube-bench image tag.

The values that matter for Sanctum: scan every namespace except `kube-system` and
`trivy-system`; `ignoreUnfixed` with `HIGH,CRITICAL` severity to match the CI
gate; and `serviceMonitor.enabled` so `HIGH`/`CRITICAL` `VulnerabilityReport`
counts reach the kube-prometheus-stack and page like any other SLO breach.

ECR is private, so the operator's ServiceAccount needs ECR read via IRSA to pull
the workload images it scans, the same grant the Kyverno verify-images policy
needs.

## What it produces

The operator watches workloads and writes findings as CRs in the workload's own
namespace, so `kubectl get` is the whole interface. No external dashboard is
required to answer "what is vulnerable right now".

| Report | Answers |
|--------|---------|
| `VulnerabilityReport` | CVEs in the images of each running workload |
| `ConfigAuditReport` | Workload misconfig (runAsNonRoot, caps, host mounts) |
| `ExposedSecretReport` | Secrets baked into image layers |
| `RbacAssessmentReport` | Over-permissive Roles/RoleBindings |

```sh
kubectl get vulnerabilityreports -n sanctum -o wide
```

Node/host-level CIS checks (the operator's infra-assessment and cluster-compliance
scanners) run a privileged node-collector that cannot live in a PSA-restricted
namespace, so they are left off. That ground is covered by the kube-bench Job in
`chambers/aws-eks/terraform/modules/platform/policies/cspm/kube-bench-job.yaml`, which audits node
and kubelet config against CIS on demand.
