# Trivy Operator is the continuous, in-cluster half of image scanning. CI scans an
# image once against the CVE database of build day; that snapshot goes stale the
# moment a new CVE lands. The operator re-scans what is actually running as the
# vulnerability database moves and writes findings as CRs (VulnerabilityReport,
# ConfigAuditReport, ExposedSecretReport, RbacAssessmentReport) in each workload's
# namespace. It is the running-cluster counterpart to the shift-left CI scan, not a
# replacement.
resource "helm_release" "trivy_operator" {
  count      = var.enable_trivy_operator ? 1 : 0
  name       = "trivy-operator"
  namespace  = kubernetes_namespace.trivy_operator[0].metadata[0].name
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  version    = var.trivy_operator_chart_version

  atomic = true
  wait   = true

  values = [
    yamlencode({
      # Empty targetNamespaces scans every namespace; carve out the control planes.
      # trivy-system is excluded so the operator does not scan its own scan Jobs, and
      # kube-system is left to the platform (its addons pull from public registries).
      targetNamespaces  = ""
      excludeNamespaces = "kube-system,trivy-system"

      trivy = {
        # Match the CI gate: alert on CVEs a base-image or dependency bump can fix,
        # do not wedge on a HIGH/CRITICAL with no upstream patch yet.
        ignoreUnfixed = true
        severity      = "HIGH,CRITICAL"
      }

      operator = {
        vulnerabilityScannerEnabled  = true
        configAuditScannerEnabled    = true
        exposedSecretScannerEnabled  = true
        rbacAssessmentScannerEnabled = true

        # Node/host-level scanning runs a privileged node-collector DaemonSet, which
        # cannot live in a PSA-restricted namespace. Node CIS is already covered by the
        # kube-bench Job in cspm.tf, so keep these off and trivy-system stays restricted.
        infraAssessmentScannerEnabled = false
        clusterComplianceEnabled      = false
      }

      # Expose the operator's Prometheus metrics to the kube-prometheus-stack so
      # HIGH/CRITICAL VulnerabilityReport counts alert like any other SLO breach.
      serviceMonitor = {
        enabled = true
      }
    })
  ]
}
