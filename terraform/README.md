# Terraform

Infrastructure for Nimbus on AWS and Cloudflare: reusable modules composed into one
root module per environment.

```
terraform/
  modules/            reusable modules (raw AWS resources or pinned community modules)
    vpc/              VPC, 3 tiers x 3 AZs, NAT, flow logs, locked default SG
    eks/              terraform-aws-modules/eks pinned, IRSA, KMS secrets, private endpoint
    rds/              PostgreSQL, Multi-AZ, KMS, PITR, Secrets Manager master password
    serverless-api/   Lambda + HTTP API, X-Ray, DLQ, SSM-sourced config
    cloudflare/       proxied DNS, strict TLS, managed WAF, rate limit, authenticated origin pulls
    github-oidc/      GitHub Actions OIDC provider + least-privilege CI role
  environments/
    dev/              cost-optimized: one NAT, single-AZ RDS, deletion protection off
    prod/             HA: NAT per AZ, Multi-AZ RDS, deletion protection on, tighter access
```

Each environment is a Terraform root module (`backend.tf`, `providers.tf`,
`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars.example`).
`main.tf` wires the modules together, passing outputs between them: VPC subnet ids
into EKS and RDS, the EKS node security group into RDS as the only allowed database
source, the EKS cluster ARN into the CI role.

## Remote state and locking

State lives in S3, one object per environment, with a distinct key
(`nimbus/dev/terraform.tfstate`, `nimbus/prod/terraform.tfstate`).

```hcl
terraform {
  backend "s3" {
    bucket         = "nimbus-tfstate-<account-id>"
    key            = "nimbus/<env>/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "nimbus-tflock"
  }
}
```

`dynamodb_table` gives a distributed lock. Terraform writes a lock item before an
apply and removes it after, so a second apply against the same state blocks instead
of interleaving writes, which is what corrupts state and produces resources Terraform
then cannot see. `encrypt = true` keeps the state object encrypted at rest, which
matters because state can hold resource attributes you would not want in plaintext.

The bucket and lock table must exist before `terraform init`. Bootstrap them once per
account (a small separate root module, or by hand) before the first init, because a
backend cannot create its own storage.

Terraform 1.11+ added native S3 lock files (`use_lockfile = true`), which removes the
DynamoDB table by using S3 conditional writes. Nimbus keeps the table because it is
the mature, widely-deployed option; a greenfield build can drop the table and set
`use_lockfile` instead.

A backend block takes no variables, so the account id is written literally per
environment. `dev` and `prod` use different placeholder accounts to model account
isolation; replace them with yours.

## Why directories, not workspaces

Environments are separate directories with separate state and their own backend, not
`terraform workspace` selections against one state file. Workspaces share a single
backend, provider configuration, and set of credentials, and the only thing telling
you which environment you are about to change is hidden CLI state, so selecting the
wrong workspace applies dev intent to prod. Separate directories give each
environment its own state, its own `terraform.tfvars`, and (in a real setup) its own
AWS account, so prod cannot be touched from a dev shell by accident.

The differences between environments are small and explicit: `dev/main.tf` sets one
NAT gateway, single-AZ RDS, and deletion protection off; `prod/main.tf` sets NAT per
AZ, Multi-AZ RDS, deletion protection on, larger nodes, and a tighter API allowlist.
Everything else is the same module calls.

At more than a couple of environments the duplicated root modules become the thing
you maintain. That is the point where a wrapper like Terragrunt earns its place: it
keeps the backend, provider, and module wiring defined once and reduces each
environment to its differing inputs. Nimbus stays on plain Terraform because two
environments do not justify the extra tool, and the toolchain flake pins Terraform
but not Terragrunt.

## Modules and versioning

Two deliberate styles live side by side:

- `vpc/` is written from raw `aws_*` resources. It is the teachable version: every
  subnet, route, and NAT gateway is visible, which is the point in a reference repo.
- `eks/` wraps `terraform-aws-modules/eks/aws` at an exact pin (`21.24.1`). Rebuilding
  the EKS control plane, IRSA, and access entries by hand is a lot of surface to get
  wrong, so here the community module is the right call.

Version pinning is layered:

- `required_version = ">= 1.6"` sets the language floor.
- Each environment's `versions.tf` pins the providers (`aws ~> 6.58`,
  `cloudflare ~> 5.22`); the modules carry matching constraints so they still validate
  on their own.
- `.terraform.lock.hcl` records exact versions and checksums on top of that. In a real
  deployment it is committed so every teammate resolves byte-identical providers. This
  study repo gitignores it for cleanliness; commit it for real work.
- Community modules are pinned to an exact version, never a range, because a module is
  not covered by the provider lock file.

## Secrets

No secret is written to state or to a committed file where it can be avoided.

- RDS uses `manage_master_user_password`, so the engine generates the password and
  stores it in a Secrets Manager secret it owns and rotates. The password never passes
  through Terraform.
- The Lambda module is handed SSM parameter ARNs, not values. The execution role gets
  `ssm:GetParameter` on exactly those ARNs and the function resolves them at runtime,
  so a `SecureString` value never lands in the plan or the state file.
- The Cloudflare API token comes from `TF_VAR_cloudflare_api_token` (or any
  environment source), never a committed `.tfvars`. `terraform.tfvars.example` shows
  the non-secret inputs and leaves the token commented out.

## Running it

Format and validate run offline with no AWS credentials:

```sh
nix develop

terraform fmt -recursive .

cd environments/dev
terraform init -backend=false      # skip the S3 backend for a local validate
terraform validate
```

Plan and apply need AWS credentials and the state backend to exist:

```sh
cd environments/dev
terraform init                     # configures the S3 backend + DynamoDB lock
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

A module can be validated on its own the same way:

```sh
cd modules/vpc && terraform init -backend=false && terraform validate
```

## IaC security scanning

Misconfiguration scanning is a merge gate, run in pre-commit
(`.pre-commit-config.yaml`) and again in CI so a bypassed hook cannot skip it.

- Checkov scans the Terraform for insecure defaults (unencrypted storage, open
  ingress, public buckets). `.checkov.yaml` sets the baseline and records the few
  suppressions, each with a reason.

  ```sh
  checkov --config-file .checkov.yaml -d .
  ```

- Trivy covers the same ground with a second engine and also scans the container
  images elsewhere in the repo, so IaC and image findings come from one tool in CI.

  ```sh
  trivy config .
  ```

Both exit non-zero on a finding at or above the configured severity, which fails the
job. Trivy is in the toolchain flake; checkov installs from pip in pre-commit and CI.
Add checkov to the flake if you want a single reproducible install.
