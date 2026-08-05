# Chamber: aws-eks

A production-shaped Kubernetes platform on AWS. Terraform and Terragrunt provision the VPC,
EKS cluster, and data tier; a Helm addon layer turns the bare cluster into a platform (Cilium
networking, ArgoCD delivery, kube-prometheus-stack observability, cert-manager, Karpenter, and
the Kyverno/Falco/Trivy security stack); GitOps delivers the workload.

## What it demonstrates

- Terraform modules composed by a Terragrunt `live/` env layer (`dev`, `prod`), S3-native state locking.
- EKS with Cilium in ENI mode (kube-proxy replacement, Hubble), Karpenter autoscaling, EKS Pod Identity.
- The `platform` module as day-1 bootstrap: addons plus all cluster-wide config (alert rules, Kyverno/Falco policies, CSPM scanners, namespace posture).
- ArgoCD ApplicationSets and SLO-gated Argo Rollouts as day-2 delivery.
- Security across the lifecycle: shift-left CI gates, cosign signing verified at admission, runtime detection, CSPM.

## Prerequisites

- An AWS account and a named CLI profile (`export AWS_PROFILE=<name>`).
- The repo toolchain: `nix develop` from the repo root.
- An S3 state bucket named `sanctum-tfstate-<account-id>`; Terragrunt creates it on first apply.

## Stand up

Units apply bottom-up by dependency (network, then cluster, then platform, with data and ci
optional). From an environment directory:

```sh
cd chambers/aws-eks/terraform/live/dev/eu-central-1
terragrunt run-all apply        # or per unit: cd network && terragrunt apply, then cluster, then platform
```

## Tear down

```sh
terragrunt run-all destroy      # reverse dependency order; remove LB-backed workloads first so NLBs/SGs are not orphaned
```

## Layout

- `terraform/modules/` - `vpc`, `eks`, `rds`, `cloudflare`, `github-oidc`, `serverless-api`, `platform`
- `terraform/live/` - Terragrunt `dev`/`prod` env layer wiring the modules

See [`terraform/README.md`](terraform/README.md) for module and Terragrunt detail, and the
repo-root `docs/` for architecture, networking, observability, and the security model.
