# platform

Cluster-infra layer for Nimbus: the shared controllers every workload depends on,
installed onto an existing EKS cluster with the Helm provider. The `eks` module builds
the cluster; this module makes it useful. Each addon is one `helm_release` in its own
file, gated by an `enable_*` toggle and pinned to an explicit chart version.

```
platform/
  providers.tf              required_providers + kubernetes/helm/kubectl auth (EKS token)
  namespaces.tf             dedicated namespaces with Pod Security Admission labels
  alb-controller.tf         AWS Load Balancer Controller + IRSA        (kube-system)
  cert-manager.tf           cert-manager + Route53 DNS01 IRSA          (cert-manager)
  external-secrets.tf       External Secrets Operator + scoped IRSA    (external-secrets)
  external-dns.tf           ExternalDNS + Route53 IRSA                 (kube-system)
  metrics-server.tf         metrics-server                            (kube-system)
  karpenter.tf              Karpenter controller + node role + SQS     (kube-system)
  kube-prometheus-stack.tf  Prometheus / Alertmanager / Grafana        (monitoring)
  argocd.tf                 Argo CD (HA off)                           (argocd)
  falco.tf                  Falco runtime detection                    (falco)
  kyverno.tf                Kyverno admission engine                   (kyverno)
```

## Provider auth

The `kubernetes`, `helm` and `kubectl` providers authenticate with a short-lived EKS
bearer token (`aws_eks_cluster_auth`), keyed off `var.cluster_name`. No kubeconfig or
exec plugin is involved, so auth follows whatever AWS credentials the caller (CI runner
or Terragrunt) already has.

## IRSA and identity

Each addon that talks to AWS gets its own IAM role scoped to a single namespace/service
account through the cluster OIDC provider:

| Addon | AWS access |
|-------|------------|
| ALB controller | managed load-balancer-controller policy |
| cert-manager | Route53 for ACME DNS01 |
| ExternalDNS | Route53 record management |
| External Secrets | custom policy: `secretsmanager:GetSecretValue` + `ssm:GetParameter*`, scoped to `nimbus/*` |
| Karpenter | controller role via EKS Pod Identity (v21 default), plus node role, instance profile and spot-interruption SQS queue |

Karpenter uses Pod Identity rather than IRSA, so the cluster needs the
`eks-pod-identity-agent` addon. Its `EC2NodeClass`/`NodePool` custom resources are day-2
config and live in `kubernetes/`, not here.

## What lives elsewhere

This module installs engines, not their configuration. Grafana dashboards and alert
rules are in `monitoring/`, Argo CD `Application` CRs in `gitops/`, Kyverno policies in
`kubernetes/security` and `security/kyverno`, and Falco custom rules in `security/falco`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | string | - | Target EKS cluster (`nimbus-dev`, `nimbus-prod`) |
| `oidc_provider_arn` | string | - | Cluster OIDC provider ARN for IRSA |
| `vpc_id` | string | - | VPC id (ALB controller) |
| `region` | string | - | AWS region (`eu-central-1`) |
| `environment` | string | - | `dev` / `prod`, used for tagging |
| `enable_<addon>` | bool | `true` | One per addon; turn an addon off |
| `<chart>_chart_version` | string | pinned | One per chart; override the default pin |

## Outputs

| Name | Description |
|------|-------------|
| `argocd_namespace` | Argo CD namespace, or `null` when disabled |
| `monitoring_namespace` | Monitoring namespace, or `null` when disabled |
| `installed_charts` | Map of installed chart name to pinned version |
