# platform

Cluster-infra layer for Nimbus: the shared controllers every workload depends on, plus
the cluster-wide config those controllers run. Installed onto an existing EKS cluster
with the Helm provider. The `eks` module builds the cluster; this module makes it useful.
Each addon is one `helm_release` in its own file, gated by an `enable_*` toggle and pinned
to an explicit chart version. Config is delivered two ways: chart-native config (rules,
routing, datasources, Falco rules) folds into the relevant `helm_release` values; non
chart-native config (ClusterPolicies, CSPM jobs, namespace posture) is applied as manifests
with `kubectl_manifest`. ArgoCD delivers only the workload app (`charts/podinfo`), nothing
cluster-wide.

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
  kube-prometheus-stack.tf  Prometheus / Alertmanager / Grafana + rules/routing/datasources
  argocd.tf                 Argo CD (HA off)                           (argocd)
  falco.tf                  Falco runtime detection + custom rules     (falco)
  kyverno.tf                Kyverno admission engine                   (kyverno)
  kyverno-policies.tf       Kyverno ClusterPolicies (supply-chain + pod-hardening)
  cspm.tf                   kube-bench Job + Prowler CronJob
  cluster-posture.tf        nimbus namespace, NetworkPolicies, RBAC, quota, LimitRange
  config/                   chart-native config read into Helm values (file()/yamldecode)
  policies/                 manifests applied via kubectl_manifest (kyverno/, cspm/, cluster/)
```

## Engines and their config

The module owns both halves of each capability: the engine and the config it runs on.

| Engine (chart) | Config it runs | Delivered as |
|----------------|----------------|--------------|
| kube-prometheus-stack | `config/prometheus-rules.yaml` (12 global alerts), `config/alertmanager.yaml` (routing/inhibitions), `config/grafana-datasources.yaml` (Loki + Tempo) | chart values (`additionalPrometheusRulesMap`, `alertmanager.config`, `grafana.additionalDataSources`) |
| Falco | `config/falco-rules.yaml` | chart value (`customRules`) |
| Kyverno | `policies/kyverno/*.yaml` (verify-images, require-signed-and-sbom, pod-security) | `kubectl_manifest`, `depends_on` the Kyverno release so the CRDs exist first |
| (core) | `policies/cspm/*.yaml` (kube-bench, prowler) | `kubectl_manifest` |
| (core) | `policies/cluster/*.yaml` (namespace, networkpolicy, rbac, resourcequota, limitrange) | `kubectl_manifest` |

Prometheus rules and Alertmanager config ride the chart, so there is no CRD-ordering
concern. The Kyverno ClusterPolicies are custom resources of the Kyverno CRDs, so
`kyverno-policies.tf` depends on the engine's `helm_release`. CSPM and cluster-posture are
core resources with no engine dependency. The `nimbus` app namespace is owned here (PSA
restricted, quota, LimitRange, default-deny); the ArgoCD ApplicationSet syncs the workload
into it, so its `CreateNamespace` option is a no-op against an existing namespace. Grafana
sidecar dashboard discovery stays on so podinfo's dashboard ConfigMaps (label
`grafana_dashboard`) still load from the app.

### nimbus namespace: posture, secrets, ingress

`policies/cluster/` is the namespace-wide baseline that has to exist before any app
lands: PSA `restricted`, a default-deny NetworkPolicy with a DNS-to-kube-dns allow, a
compute `ResourceQuota` and a `LimitRange`, and a least-privilege `Role` scoped by
`resourceNames` to the workload's own ConfigMap and Secret. The app reopens exactly the
network paths it needs (ingress on 9898 from the ALB subnet and Prometheus, egress to the
data stores and the OTel collector) through its own chart-scoped policies, so the app's
network surface travels with the app.

Secrets never reach Git. The workload loads a `podinfo-secrets` Secret by name via
`envFrom.secretRef`; provision it out of band from AWS Secrets Manager (the External
Secrets Operator installed here, or the CSI driver) so credentials stay out of the repo.
The scoped, by-name secret read in `policies/cluster/rbac.yaml` is what the RBAC guardrail
protects.

Ingress is an ALB via the AWS Load Balancer Controller (`ingressClassName: alb`), not
ingress-nginx, to match the edge path (Cloudflare -> ALB -> EKS) and to attach an AWS
WAFv2 web ACL; TLS terminates at the ALB with an ACM certificate. With `target-type: ip`
the ALB connects from its ENIs in the load-balancer subnets straight to pod IPs, which is
why the app's ingress NetworkPolicy allows a subnet CIDR rather than a controller
namespace. The Ingress object itself ships with the app in `charts/podinfo`.

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
tuning and are not delivered by this module.

## What lives elsewhere

This module owns the engines and their cluster-wide config. What it does not own: the
workload itself (`charts/podinfo`, the podinfo Helm chart with its own ServiceMonitor,
PrometheusRule, dashboards and scoped NetworkPolicies) and the delivery CRs that sync it
(`gitops/`, the ArgoCD `AppProject` + `ApplicationSet`). ArgoCD delivers only that app;
everything cluster-wide is Terraform's job.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | string | - | Target EKS cluster (`nimbus-dev`, `nimbus-prod`) |
| `oidc_provider_arn` | string | - | Cluster OIDC provider ARN for IRSA |
| `vpc_id` | string | - | VPC id (ALB controller) |
| `region` | string | - | AWS region (`eu-central-1`) |
| `environment` | string | - | `dev` / `prod`, used for tagging |
| `enable_<addon>` | bool | `true` | One per addon; turn an addon off |
| `enable_kyverno_policies` | bool | `true` | Deliver the Kyverno ClusterPolicies (requires `enable_kyverno`) |
| `enable_cspm` | bool | `true` | Deliver the CSPM scanners (kube-bench, Prowler) |
| `enable_cluster_posture` | bool | `true` | Deliver the nimbus namespace posture (NetworkPolicy, RBAC, quota, LimitRange) |
| `<chart>_chart_version` | string | pinned | One per chart; override the default pin |

## Outputs

| Name | Description |
|------|-------------|
| `argocd_namespace` | Argo CD namespace, or `null` when disabled |
| `monitoring_namespace` | Monitoring namespace, or `null` when disabled |
| `installed_charts` | Map of installed chart name to pinned version |
