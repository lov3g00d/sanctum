# Kubernetes: cluster and namespace security

The `nimbus` application itself is now a Helm chart under
[`charts/podinfo`](../charts/podinfo); this directory holds only the cluster and
namespace security scaffolding that has to exist before any app lands. The split
is deliberate: the guardrails are applied once per cluster and are owned by the
platform, so a broken app change cannot touch them, and the cluster-scoped
policies are not duplicated per environment.

The deployable workload is upstream
[`podinfo`](https://github.com/stefanprodan/podinfo), a public, reproducible test
image that stands in for the core service so the platform can be exercised end to
end without shipping bespoke app code.

## Layout

```
kubernetes/
  security/             cluster + namespace bootstrap, applied once
    namespace.yaml      Pod Security Admission enforce=restricted
    networkpolicy.yaml  default-deny + namespace-wide DNS baseline
    rbac.yaml           least-privilege Role + RoleBinding
    resourcequota.yaml  namespace compute ceiling
    limitrange.yaml     default requests/limits
    kyverno-policies.yaml  admission guardrails
    kustomization.yaml
```

The app's own workload, ingress, HPA, PDB, ServiceAccount, ConfigMap and its
podinfo-scoped NetworkPolicy/CiliumNetworkPolicy live in the chart. Only the
namespace default-deny and the namespace-wide DNS allow stay here, because they
apply to every pod in `nimbus`, not just podinfo.

## Build and apply

```sh
# Bootstrap the namespace, policies and guardrails (once per cluster)
kustomize build kubernetes/security | kubectl apply -f -

# Deploy the app with Helm (or let ArgoCD do it from gitops/)
helm upgrade --install podinfo charts/podinfo \
  --namespace nimbus --create-namespace \
  -f charts/podinfo/values.yaml -f charts/podinfo/values-prod.yaml
```

Secrets are not in Git. The workload loads them from a `podinfo-secrets` Secret
referenced by name via `envFrom.secretRef`; provision it out of band from AWS
Secrets Manager (External Secrets Operator or the CSI driver) so credentials never
reach the repo. podinfo itself needs no secret to run; the reference is kept so
the scoped, least-privilege secret read stays part of the manifest set.

## Security posture

- **Pod Security Admission `restricted`.** The `nimbus` namespace is labelled to
  enforce, audit and warn at the restricted level. Pods that request privilege,
  host namespaces, or writable roots are rejected at admission.
- **Non-root, read-only containers.** The chart's pod template sets
  `runAsNonRoot` with a non-zero UID/GID, `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, all Linux capabilities dropped, and
  `seccompProfile: RuntimeDefault`. The only writable path is an `emptyDir`
  mounted at `/tmp`.
- **Default-deny NetworkPolicy.** This directory denies all ingress and egress in
  `nimbus`, then reopens DNS to kube-dns for the whole namespace. The app then
  reopens exactly what it needs (ingress on 9898 from the ALB subnet and from
  Prometheus, egress to RDS/Redis and to the OTel collector) through its own
  chart-scoped policies, so the app's network surface travels with the app.
- **Least-privilege RBAC.** A namespaced Role grants read-only access to the
  workload's own ConfigMap and Secret by name; nothing cluster-wide.
- **IRSA.** The chart's ServiceAccount carries an `eks.amazonaws.com/role-arn`
  annotation (wired per environment); AWS access comes from a scoped IAM role via
  web identity, not node credentials.
- **Kyverno.** ClusterPolicies re-assert the same invariants (no `:latest`,
  non-root, read-only root, resource limits, drop-all capabilities) with
  PolicyReports for visibility. See the note in `security/kyverno-policies.yaml`
  on rolling out Audit before Enforce.

## Ingress choice

The app ships an ALB Ingress via the AWS Load Balancer Controller
(`ingressClassName: alb`), not ingress-nginx, to match the scenario edge path
(Cloudflare -> ALB -> EKS) and to associate an AWS WAFv2 web ACL. TLS terminates
at the ALB with an ACM certificate. With `target-type: ip` the ALB connects from
its ENIs in the load-balancer subnets straight to pod IPs, which is why the
ingress NetworkPolicy allows a subnet CIDR rather than a controller namespace. The
`10.0.x.x` CIDRs and the account/ARN placeholders are wired to real values by
Terraform and the chart's values files.
