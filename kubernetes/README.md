# Kubernetes: nimbus-orders-api

Kustomize manifests for the always-on core API on EKS. The layout separates the
application workload (Kustomize base + per-env overlays) from the cluster and
namespace security scaffolding, so a broken app change cannot touch the guardrails
and the cluster-scoped policies are not duplicated per environment.

## Layout

```
kubernetes/
  base/                 app workload, environment-agnostic
    deployment.yaml     hardened securityContext, probes, topology spread
    service.yaml        ClusterIP 80 -> 3000
    ingress.yaml        ALB ingress, TLS via ACM, WAFv2 assoc.
    serviceaccount.yaml IRSA role-arn annotation
    configmap.yaml      non-secret config (endpoints, log level, region)
    hpa.yaml            autoscaling/v2, CPU + memory
    pdb.yaml            minAvailable 50%
    kustomization.yaml
  overlays/
    dev/                replicas 2, smaller requests, debug logging
    prod/               replicas 4, larger requests, DoNotSchedule spread
  security/             cluster + namespace bootstrap, applied once
    namespace.yaml      Pod Security Admission enforce=restricted
    networkpolicy.yaml  default-deny + explicit allows
    rbac.yaml           least-privilege Role + RoleBinding
    resourcequota.yaml  namespace compute ceiling
    limitrange.yaml     default requests/limits
    kyverno-policies.yaml  admission guardrails
```

## Build and apply

```sh
# Bootstrap the namespace, policies and guardrails (once per cluster)
kustomize build kubernetes/security | kubectl apply -f -

# Deploy the app for an environment
kustomize build kubernetes/overlays/prod | kubectl apply -f -
kustomize build kubernetes/overlays/dev  | kubectl apply -f -
```

Secrets are not in Git. The Deployment loads them from a `nimbus-orders-api-secrets`
Secret referenced by name via `envFrom.secretRef`; provision it out of band from AWS
Secrets Manager (External Secrets Operator or the CSI driver) so credentials never
reach the repo. Only `configmap.yaml` carries real, non-secret values.

## Security posture

- **Pod Security Admission `restricted`.** The `nimbus` namespace is labelled to
  enforce, audit and warn at the restricted level. Pods that request privilege,
  host namespaces, or writable roots are rejected at admission.
- **Non-root, read-only containers.** `runAsNonRoot` with a non-zero UID/GID,
  `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, all Linux
  capabilities dropped, and `seccompProfile: RuntimeDefault`. The only writable
  path is an `emptyDir` mounted at `/tmp`.
- **Default-deny NetworkPolicy.** Ingress and egress are denied, then reopened for
  exactly what the app needs: DNS to kube-dns, ingress on 3000 from the ALB subnet
  and from Prometheus in `monitoring`, and egress to RDS (5432) and Redis (6379).
- **Least-privilege RBAC.** A namespaced Role grants read-only access to the
  workload's own ConfigMap and Secret by name; nothing cluster-wide.
- **IRSA.** The ServiceAccount carries an `eks.amazonaws.com/role-arn` annotation;
  AWS access comes from a scoped IAM role via web identity, not node credentials.
- **Kyverno.** ClusterPolicies re-assert the same invariants (no `:latest`,
  non-root, read-only root, resource limits, drop-all capabilities) with
  PolicyReports for visibility. See the note in `security/kyverno-policies.yaml`
  on rolling out Audit before Enforce.

## Ingress choice

ALB via the AWS Load Balancer Controller (`ingressClassName: alb`), not
ingress-nginx, to match the scenario edge path (Cloudflare -> ALB -> EKS) and to
associate an AWS WAFv2 web ACL. TLS terminates at the ALB with an ACM certificate.
With `target-type: ip` the ALB connects from its ENIs in the load-balancer subnets
straight to pod IPs, which is why the ingress NetworkPolicy allows a subnet CIDR
rather than a controller namespace. The `10.0.x.x` CIDRs and the account/ARN
placeholders are wired to real values by Terraform.
