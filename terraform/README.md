# Terraform

Infrastructure for Nimbus on AWS and Cloudflare: reusable modules composed by a
Terragrunt `live/` layer, one unit per concern per environment.

```
terraform/
  modules/            reusable modules (raw AWS resources or pinned community modules)
    vpc/              VPC, 3 tiers x 3 AZs, NAT, flow logs, locked default SG
    eks/              terraform-aws-modules/eks pinned, IRSA, KMS secrets, private endpoint
    rds/              PostgreSQL, Multi-AZ, KMS, PITR, Secrets Manager master password
    cloudflare/       proxied DNS, strict TLS, managed WAF, rate limit, authenticated origin pulls
    github-oidc/      GitHub Actions OIDC provider + least-privilege CI role
    platform/         Helm addon layer via helm_release + per-chart IRSA
  live/               Terragrunt env layer
    root.hcl          remote state (S3 + DynamoDB) + generated provider, reads env.hcl
    dev/  prod/       env.hcl (account, ha flag) + eu-central-1/<unit>/terragrunt.hcl
```

Each `live/<env>/eu-central-1/<unit>` is a thin `terragrunt.hcl` pointing at a module
in `modules/`, with `dependency` blocks passing outputs between units (VPC subnet ids
into EKS and RDS, the EKS node security group into RDS as the only allowed database
source, cluster name and OIDC provider into the platform layer). Environment
differences live only in `env.hcl`.

## Remote state and locking

State lives in S3, one object per unit, keyed by `live/<path>/terraform.tfstate`. The
backend and provider are generated once in `root.hcl` so no unit repeats them.

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket       = "nimbus-tfstate-<account-id>"
    key          = "live/${path_relative_to_include()}/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

`use_lockfile = true` is S3-native locking (Terraform 1.11+ / OpenTofu): the backend
writes a `<key>.tflock` object via an S3 conditional write, so a second apply against
the same state blocks instead of interleaving writes. It replaces the separate DynamoDB
lock table, which the S3 backend now deprecates. `encrypt = true` keeps the state object
encrypted at rest, which matters because state can hold resource attributes you would
not want in plaintext.

The bucket must exist before the first run. Bootstrap it once per account (a small
separate root module, or by hand), because a backend cannot create its own storage.

## Why Terragrunt, and why units

Environments are separate state, provider config, and (in a real setup) separate AWS
accounts, not `terraform workspace` selections against one state file. Workspaces share
a single backend and the only thing telling you which environment you are about to
change is hidden CLI state, so selecting the wrong workspace applies dev intent to prod.

Terragrunt keeps the backend, provider, and module wiring defined once in `root.hcl`
and reduces each environment to its differing inputs in `env.hcl`. Splitting each
environment into units (network, cluster, data, edge, ci, platform) keeps blast radius
small: a change to the edge does not re-plan the cluster, and `dependency` blocks make
the data flow between units explicit.

## Modules and versioning

Two deliberate styles live side by side:

- `vpc/` is written from raw `aws_*` resources. It is the teachable version: every
  subnet, route, and NAT gateway is visible.
- `eks/` wraps `terraform-aws-modules/eks/aws` at an exact pin (`21.24.1`). Rebuilding
  the control plane, IRSA, and access entries by hand is a lot of surface to get wrong,
  so the community module is the right call.

Version pinning is layered:

- `required_version >= 1.6` sets the language floor.
- Each module's `versions.tf` pins the providers (`aws ~> 6.58`, `cloudflare ~> 5.22`)
  so it validates on its own.
- Community modules are pinned to an exact version, never a range, because a module is
  not covered by the provider lock file.
- `.terraform.lock.hcl` records exact provider versions and checksums. This repo
  gitignores it for cleanliness; commit it for real deployments so every teammate
  resolves byte-identical providers.

## Secrets

No secret is written to state or a committed file where it can be avoided.

- RDS uses `manage_master_user_password`, so the engine generates the password and
  stores it in a Secrets Manager secret it owns and rotates. The password never passes
  through Terraform.
- The Cloudflare API token comes from `TF_VAR_cloudflare_api_token` (or any environment
  source), never a committed `.tfvars`.

## Running it

Modules validate offline with no AWS credentials:

```sh
nix develop
terraform fmt -recursive .
cd modules/vpc && terraform init -backend=false && terraform validate
```

The Terragrunt layer validates its wiring offline (dependency outputs are mocked):

```sh
cd live
terragrunt hcl fmt --check
terragrunt hcl validate --all
```

Plan and apply need AWS credentials and the state backend to exist:

```sh
cd live/dev/eu-central-1/cluster
terragrunt plan
terragrunt apply
```

To plan only the AWS units against an account with no Cloudflare zone, run the units
you want (or `terragrunt run-all plan` after excluding the `edge` unit) rather than a
provider toggle.

## IaC security scanning

Misconfiguration scanning is a merge gate, run in pre-commit
(`.pre-commit-config.yaml`) and again in CI so a bypassed hook cannot skip it.

- Checkov scans the Terraform for insecure defaults (unencrypted storage, open ingress,
  public buckets), with suppressions recorded and justified.

  ```sh
  checkov -d .
  ```

- Trivy covers the same ground with a second engine and also scans the container images
  elsewhere in the repo.

  ```sh
  trivy config .
  ```

Both exit non-zero on a finding at or above the configured severity, which fails the
job. Trivy is in the toolchain flake; checkov installs from pip in pre-commit and CI.
