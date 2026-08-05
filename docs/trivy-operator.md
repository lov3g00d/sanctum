# Trivy Operator: in-cluster posture

CI (`cicd/ci.yml`) scans images once, at build time, against the CVE database of
that day. That snapshot goes stale: a new CVE published after the image ships is
invisible until the next rebuild. Trivy Operator closes that gap by scanning
what is actually running, continuously, from inside the cluster, and by
re-scanning as the vulnerability database updates.

It is the running-cluster counterpart to the shift-left image scan, not a
replacement. CI blocks a bad image from ever being built; the operator catches
the image that was clean when built and became vulnerable in place.

## What it produces

The operator watches workloads and writes findings as CRs in the workload's own
namespace, so `kubectl get` is the whole interface. No external dashboard is
required to answer "what is vulnerable right now".

| Report | Answers |
|--------|---------|
| `VulnerabilityReport` | CVEs in the images of each running workload |
| `ExposedSecretReport` | Secrets baked into image layers |
| `ConfigAuditReport` | Workload misconfig (runAsNonRoot, caps, host mounts) |
| `RbacAssessmentReport` | Over-permissive Roles/RoleBindings |
| `InfraAssessmentReport` | Node/kubelet config (CIS node checks) |
| `ClusterComplianceReport` | Rolled-up CIS Kubernetes / NSA / PSS compliance |

```sh
kubectl get vulnerabilityreports -n nimbus -o wide
kubectl get clustercompliancereport cis -o yaml
```

The `ClusterComplianceReport` overlaps kube-bench
(`terraform/modules/platform/policies/cspm/kube-bench-job.yaml`): both
score CIS Kubernetes. kube-bench is a point-in-time node audit run on demand;
Trivy Operator keeps a continuously-updated cluster-wide compliance object. Run
both, they answer the question at different cadences.

## Minimal install (Helm)

Deployed by the platform module in the reference setup; the values that matter
for Nimbus:

```yaml
# helm upgrade --install trivy-operator aqua/trivy-operator \
#   --namespace trivy-system --create-namespace \
#   --version <pin> -f values.yaml
targetNamespaces: "nimbus"        # scope scanning to the app namespace
trivy:
  # ECR is private: the operator resolves the workload's imagePullSecrets /
  # the node IRSA to pull. Give its ServiceAccount ECR read via IRSA in
  # terraform, same grant the Kyverno verify-images policy needs.
  ignoreUnfixed: true             # match CI: alert on what a bump can fix
  severity: "HIGH,CRITICAL"
operator:
  scannerReportTTL: "24h"         # re-scan daily as the CVE DB moves
  vulnerabilityScannerEnabled: true
  configAuditScannerEnabled: true
  rbacAssessmentScannerEnabled: true
  clusterComplianceEnabled: true
compliance:
  # Emit the CIS Kubernetes compliance report object.
  specs:
    - k8s-cis
```

Pin `--version` to a specific chart release and bump it as a reviewed change,
the same discipline applied to the kube-bench image tag. Route
`HIGH`/`CRITICAL` `VulnerabilityReport` counts and the `ClusterComplianceReport`
score into the kube-prometheus-stack the platform installs (the operator exposes
metrics)
so a workload drifting out of compliance pages the same way an SLO breach does.
