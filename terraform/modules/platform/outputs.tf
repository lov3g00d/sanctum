output "argocd_namespace" {
  description = "Namespace Argo CD is installed in, or null when disabled."
  value       = one(kubernetes_namespace.argocd[*].metadata[0].name)
}

output "monitoring_namespace" {
  description = "Namespace the kube-prometheus-stack is installed in, or null when disabled."
  value       = one(kubernetes_namespace.monitoring[*].metadata[0].name)
}

output "installed_charts" {
  description = "Map of installed addon chart names to their pinned versions."
  value = merge(
    var.enable_alb_controller ? { "aws-load-balancer-controller" = var.alb_controller_chart_version } : {},
    var.enable_cert_manager ? { "cert-manager" = var.cert_manager_chart_version } : {},
    var.enable_external_secrets ? { "external-secrets" = var.external_secrets_chart_version } : {},
    var.enable_external_dns ? { "external-dns" = var.external_dns_chart_version } : {},
    var.enable_metrics_server ? { "metrics-server" = var.metrics_server_chart_version } : {},
    var.enable_karpenter ? { "karpenter" = var.karpenter_chart_version } : {},
    var.enable_kube_prometheus_stack ? { "kube-prometheus-stack" = var.kube_prometheus_stack_chart_version } : {},
    var.enable_argocd ? { "argo-cd" = var.argocd_chart_version } : {},
    var.enable_falco ? { "falco" = var.falco_chart_version } : {},
    var.enable_kyverno ? { "kyverno" = var.kyverno_chart_version } : {},
  )
}
