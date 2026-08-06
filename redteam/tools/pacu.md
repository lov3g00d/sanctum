# Pacu - AWS exploitation framework (IAM privesc enumeration)

Pacu is Rhino Security Labs' offensive AWS toolkit. Here it is used for one
thing: enumerate the IAM attack surface of the sandbox account and confirm
there is no privilege-escalation path a compromised role could walk. It is the
offensive counterpart to the Prowler CSPM run
(`terraform/modules/platform/policies/cspm/prowler-cronjob.yaml`): Prowler scores
the account against CIS benchmarks; Pacu asks the attacker's question, "given
these credentials, can I escalate?"

## Scope and authorization

- Target: the operator's OWN sandbox AWS account `123456789012`, nothing else.
- Credentials: the read-only `SecurityAudit` + `ViewOnlyAccess` identity already
  used by the CSPM tooling. Pacu is driven read-only here: run enumeration
  modules, not the exploitation modules that create or modify resources.
- Never point Pacu at an account you do not own. Pacu is interactive and can
  mutate IAM, S3, EC2, and more. Everything below stays on read-only enum
  modules; do not run `*__backdoor_*`, `*__create_*`, or the exploit variants.

## Run it in a container

Pacu is interactive, so run it in a throwaway container with the read-only
credentials injected from the environment (never bake keys into the image).
Prefer short-lived STS credentials from an assumed read-only role over static
keys.

```
docker run --rm -it \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e AWS_DEFAULT_REGION=eu-central-1 \
  rhinosecuritylabs/pacu:latest
```

Inside the Pacu shell:

```
import_keys --all
whoami
```

`import_keys --all` pulls the credentials from the environment into a Pacu key
set; `whoami` confirms which principal Pacu is operating as before anything
runs.

## Enumeration modules to run

Run these in order. All are read-only: they call `List*`, `Get*`, and
`Simulate*`, which the `SecurityAudit` policy already permits.

| Module | What it answers |
|--------|-----------------|
| `iam__enum_users_roles_policies_groups` | Full inventory of principals and attached/inline policies |
| `iam__enum_permissions` | Resolves the effective permission set for the current principal |
| `iam__privesc_scan` | Flags known IAM privilege-escalation paths (run enumeration only, decline the exploit prompt) |
| `iam__enum_roles` | Cross-account and assumable roles reachable from here |

```
run iam__enum_users_roles_policies_groups
run iam__enum_permissions
run iam__privesc_scan
```

`iam__privesc_scan` will offer to attempt any path it finds. Answer no. The
finding itself is the deliverable: a reported path is a misconfiguration to fix
in `terraform/`, not something to exploit.

## Reading the result

A clean run reports no privilege-escalation path for the audited principal.
That is the expected outcome and validates the least-privilege IAM design:
split OIDC roles (deploy / tf-plan / tf-apply), scoped trust policies, and no
broad `iam:*` or `*:*` grants.

If Pacu reports a path (for example `PassRole` to a more privileged role, or
attachable admin policies), treat it as a finding: capture the module output,
open a fix in the Terraform IAM module, and re-run to confirm it closes. Feed
the same finding to Prowler's IAM checks so the drift is caught continuously,
not only when someone runs Pacu by hand.
