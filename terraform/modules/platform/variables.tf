variable "cluster_name" {
  description = "Name of the target EKS cluster (e.g. nimbus-dev, nimbus-prod)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster IRSA/OIDC provider. Used to scope the addon IAM roles to their service accounts."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in. Required by the AWS Load Balancer Controller."
  type        = string
}

variable "region" {
  description = "AWS region the cluster runs in (eu-central-1 for Nimbus)."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, prod). Used for resource tagging."
  type        = string
}

# Addon toggles. Everything defaults on so a plain `terraform apply` yields the full
# platform layer; a Terragrunt env can trim it per environment.

variable "enable_cilium" {
  description = "Install Cilium as the primary CNI and kube-proxy replacement."
  type        = bool
  default     = true
}

variable "enable_alb_controller" {
  description = "Install the AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "enable_cert_manager" {
  description = "Install cert-manager."
  type        = bool
  default     = true
}

variable "enable_external_secrets" {
  description = "Install the External Secrets Operator."
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Install ExternalDNS."
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Install metrics-server (required by HPA and `kubectl top`)."
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Install Karpenter for node autoscaling."
  type        = bool
  default     = true
}

variable "enable_kube_prometheus_stack" {
  description = "Install the kube-prometheus-stack (Prometheus, Alertmanager, Grafana)."
  type        = bool
  default     = true
}

variable "enable_argocd" {
  description = "Install Argo CD."
  type        = bool
  default     = true
}

variable "enable_falco" {
  description = "Install Falco for runtime threat detection."
  type        = bool
  default     = true
}

variable "enable_kyverno" {
  description = "Install Kyverno as the policy admission engine."
  type        = bool
  default     = true
}

# Chart versions. Pinned so an apply is reproducible; bump deliberately per chart.

variable "cilium_chart_version" {
  description = "Cilium chart version."
  type        = string
  default     = "1.20.0"
}

variable "alb_controller_chart_version" {
  description = "aws-load-balancer-controller chart version."
  type        = string
  default     = "1.13.4"
}

variable "cert_manager_chart_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.19.3"
}

variable "external_secrets_chart_version" {
  description = "external-secrets chart version."
  type        = string
  default     = "1.2.1"
}

variable "external_dns_chart_version" {
  description = "external-dns chart version."
  type        = string
  default     = "1.19.0"
}

variable "metrics_server_chart_version" {
  description = "metrics-server chart version."
  type        = string
  default     = "3.13.0"
}

variable "karpenter_chart_version" {
  description = "Karpenter chart version (OCI)."
  type        = string
  default     = "1.14.0"
}

variable "kube_prometheus_stack_chart_version" {
  description = "kube-prometheus-stack chart version."
  type        = string
  default     = "88.1.5"
}

variable "argocd_chart_version" {
  description = "argo-cd chart version."
  type        = string
  default     = "10.3.0"
}

variable "falco_chart_version" {
  description = "falco chart version."
  type        = string
  default     = "9.1.0"
}

variable "kyverno_chart_version" {
  description = "kyverno chart version."
  type        = string
  default     = "3.8.2"
}
