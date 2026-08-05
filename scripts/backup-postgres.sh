#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: backup-postgres.sh

Dumps a PostgreSQL database with pg_dump, gzips it, uploads it server-side
encrypted to S3 under a dated key, then prunes objects older than the
retention window. Intended to run from a cron job or systemd timer.

Required environment:
  PGHOST                Database host
  PGDATABASE            Database name
  PGUSER                Database user
  PGPASSWORD            Database password (prefer injection from a secret store)
  S3_BUCKET             Target bucket name (no s3:// prefix)

Optional environment:
  PGPORT                Database port (default: 5432)
  S3_PREFIX             Key prefix (default: sanctum/postgres)
  BACKUP_RETENTION_DAYS Days to keep (default: 14)
  SSE_MODE              aws:kms | AES256 (default: aws:kms)
  SSE_KMS_KEY_ID        KMS key id/ARN, required only for a customer-managed key
  AWS_REGION            AWS region (default: eu-central-1)
EOF
}

WORKDIR=""
cleanup() {
  local rc=$?
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf -- "$WORKDIR"
  fi
  if (( rc != 0 )); then
    log ERROR "backup failed with status ${rc}"
  fi
}
trap cleanup EXIT

require_env() {
  local var missing=0
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      log ERROR "required environment variable unset: ${var}"
      missing=1
    fi
  done
  (( missing == 0 )) || die "aborting: required environment is incomplete"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 2
  fi

  require_cmd pg_dump gzip aws date
  require_env PGHOST PGDATABASE PGUSER PGPASSWORD S3_BUCKET

  local pgport="${PGPORT:-5432}"
  local prefix="${S3_PREFIX:-sanctum/postgres}"
  local retention="${BACKUP_RETENTION_DAYS:-14}"
  local sse_mode="${SSE_MODE:-aws:kms}"
  local region="${AWS_REGION:-eu-central-1}"

  prefix="${prefix#/}"
  prefix="${prefix%/}"

  local stamp
  stamp="$(date -u +%Y/%m/%d/%H%M%S)"
  local key="${prefix}/${PGDATABASE}/${stamp}.sql.gz"

  WORKDIR="$(mktemp -d -t sanctum-pgbackup.XXXXXX)"
  local dump_file="${WORKDIR}/dump.sql.gz"

  log INFO "dumping ${PGDATABASE} from ${PGHOST}:${pgport}"
  PGPASSWORD="$PGPASSWORD" pg_dump \
    --host="$PGHOST" --port="$pgport" --username="$PGUSER" \
    --dbname="$PGDATABASE" --no-owner --no-privileges \
    | gzip -9 >"$dump_file"

  local sse_args=(--sse "$sse_mode")
  if [[ "$sse_mode" == "aws:kms" && -n "${SSE_KMS_KEY_ID:-}" ]]; then
    sse_args+=(--sse-kms-key-id "$SSE_KMS_KEY_ID")
  fi

  local dest="s3://${S3_BUCKET}/${key}"
  log INFO "uploading ${dest} (sse=${sse_mode})"
  retry_with_backoff 3 2 \
    aws --region "$region" s3 cp "$dump_file" "$dest" "${sse_args[@]}" \
    || die "upload failed: ${dest}"

  prune_old "$region" "$prefix" "$retention"

  log INFO "backup complete: ${dest}"
}

prune_old() {
  local region="$1" prefix="$2" retention="$3"
  local cutoff_epoch
  cutoff_epoch="$(date -u -d "-${retention} days" +%s)"

  log INFO "pruning objects older than ${retention} days under ${prefix}/"

  # JMESPath ordering comparisons are number-only; against botocore's datetime
  # LastModified they match nothing. Pull Key+LastModified and compare epochs
  # in the shell instead.
  local listing
  listing="$(aws --region "$region" s3api list-objects-v2 \
    --bucket "$S3_BUCKET" --prefix "${prefix}/" \
    --query 'Contents[].[Key,LastModified]' --output text)"

  if [[ -z "$listing" || "$listing" == "None" ]]; then
    log INFO "nothing to prune"
    return 0
  fi

  local key lastmod obj_epoch pruned=0
  while IFS=$'\t' read -r key lastmod; do
    [[ -n "$key" ]] || continue
    obj_epoch="$(date -u -d "$lastmod" +%s)"
    if (( obj_epoch <= cutoff_epoch )); then
      log INFO "deleting s3://${S3_BUCKET}/${key}"
      aws --region "$region" s3api delete-object \
        --bucket "$S3_BUCKET" --key "$key" >/dev/null
      pruned=$(( pruned + 1 ))
    fi
  done <<<"$listing"

  log INFO "pruned ${pruned} object(s)"
}

main "$@"
