# scripts/

Hardened operational Bash for the Nimbus platform. Every script uses strict mode
(`set -euo pipefail`, `IFS=$'\n\t'`), a `usage()` function, argument/environment
validation, an exit-time cleanup trap, and quoted expansions. All are
shellcheck-clean.

## Layout

| Path | Purpose |
|------|---------|
| `lib/common.sh` | Sourced helpers: `log`, `die`, `require_cmd`, `retry_with_backoff`. Not executable on its own. |
| `health-check.sh` | External liveness/readiness probe for a service. |
| `backup-postgres.sh` | Dump RDS PostgreSQL to encrypted S3 with retention pruning. |
| `ec2-user-data.sh` | First-boot bootstrap for a hardened Amazon Linux 2023 host. |

`lib/common.sh` deliberately omits the strict-mode header and traps: a sourced
library must not change the caller's shell options or install traps. The script
that sources it owns those.

## health-check.sh

Probes `/healthz` then `/readyz` with `curl`, retrying each with exponential
backoff, and exits non-zero if either stays unhealthy. Both endpoints are part
of the podinfo contract on port 9898 (see `docker/README.md`), so the probe works
against podinfo directly.

```sh
./health-check.sh https://api.nimbus.example.com 5
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `HEALTH_MAX_ATTEMPTS` | 4 | Retry attempts per endpoint |
| `HEALTH_BASE_DELAY` | 1 | Initial backoff seconds (doubles each retry) |

Fits as an external synthetic check (cron, a monitoring runner, or a Cloudflare
health check) that is independent of the in-cluster Kubernetes probes.

## backup-postgres.sh

`pg_dump` -> `gzip -9` -> server-side-encrypted `s3 cp` under a dated key ->
prune objects older than the retention window. Connection details come
from the environment only; the script refuses to run if any required variable is
unset.

| Variable | Required | Default | Meaning |
|----------|:--------:|---------|---------|
| `PGHOST` | yes | | Database host |
| `PGDATABASE` | yes | | Database name |
| `PGUSER` | yes | | Database user |
| `PGPASSWORD` | yes | | Password (inject from Secrets Manager, do not hardcode) |
| `S3_BUCKET` | yes | | Target bucket, no `s3://` prefix |
| `PGPORT` | no | 5432 | Database port |
| `S3_PREFIX` | no | `nimbus/postgres` | Key prefix |
| `BACKUP_RETENTION_DAYS` | no | 14 | Days to keep |
| `SSE_MODE` | no | `aws:kms` | `aws:kms` or `AES256` |
| `SSE_KMS_KEY_ID` | no | | Customer-managed key id/ARN (KMS only) |
| `AWS_REGION` | no | `eu-central-1` | AWS region |

Run it from a systemd timer or cron on a bastion/ops host with an instance role
scoped to the backup bucket and KMS key. Example key layout:
`nimbus/postgres/<db>/YYYY/MM/DD/HHMMSS.sql.gz`.

```sh
# /etc/cron.d/nimbus-pg-backup  (env from an EnvironmentFile or Secrets Manager)
15 2 * * * ops /opt/nimbus/scripts/backup-postgres.sh
```

## ec2-user-data.sh

Launch-template User data for a hardened AL2023 host. It updates packages,
ensures the preinstalled SSM agent is enabled, installs and enables the
CloudWatch agent, disables SSH password auth and root login via an
`sshd_config.d` drop-in that sorts ahead of cloud-init's, and sets the hostname
from the instance `Name` tag. The instance role needs `ec2:DescribeTags` for the
tag lookup and the SSM/CloudWatch managed policies for the agents.

Paste it into the launch template's User data field. It is idempotent where
practical, so a cloud-init retry converges instead of duplicating state.
