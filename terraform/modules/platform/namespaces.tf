locals {
  common_tags = {
    Project     = "nimbus"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "platform-team"
  }
}

# Dedicated namespaces for the addons that get their own. kube-system hosted addons
# (ALB controller, ExternalDNS, metrics-server, Karpenter) reuse the existing system
# namespace and are not created here.
#
# Pod Security Admission is set per namespace. Falco and the monitoring node-exporter
# need host access (syscalls, hostNetwork/hostPID) so they run "privileged"; everything
# else is pinned to "restricted".

resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  count = var.enable_kube_prometheus_stack ? 1 : 0

  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_namespace" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_namespace" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  metadata {
    name = "cert-manager"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_namespace" "falco" {
  count = var.enable_falco ? 1 : 0

  metadata {
    name = "falco"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_namespace" "kyverno" {
  count = var.enable_kyverno ? 1 : 0

  metadata {
    name = "kyverno"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}
