#!/usr/bin/env bash
#
# EC2 user-data / cloud-init bootstrap for a hardened Amazon Linux 2023 host.
# Runs once at first boot as root. Idempotent where practical so a re-run (or a
# cloud-init retry) converges rather than duplicating state.
#
# Launch-template usage: paste this as the instance User data. It reads the
# instance's own tags via IMDSv2, so the role must allow ec2:DescribeTags.
set -euo pipefail
IFS=$'\n\t'

log() {
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${*:2}" >&2
}
die() {
  log ERROR "${*}"
  exit 1
}

on_err() {
  log ERROR "bootstrap failed at line ${1}"
}
trap 'on_err "${LINENO}"' ERR

readonly HARDEN_DROPIN="/etc/ssh/sshd_config.d/00-nimbus-hardening.conf"

update_packages() {
  log INFO "applying package updates"
  dnf -y update
}

install_agents() {
  # The SSM agent ships preinstalled on AL2023; ensure it is enabled and running.
  log INFO "enabling amazon-ssm-agent"
  systemctl enable --now amazon-ssm-agent

  log INFO "installing amazon-cloudwatch-agent"
  dnf -y install amazon-cloudwatch-agent
  systemctl enable amazon-cloudwatch-agent
}

harden_ssh() {
  log INFO "hardening sshd"
  # A drop-in sorted before cloud-init's 50-cloud-init.conf wins under sshd's
  # first-value-per-directive rule, so this disables the password auth that
  # cloud-init would otherwise re-enable.
  cat >"$HARDEN_DROPIN" <<'EOF'
PasswordAuthentication no
PermitRootLogin no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
EOF
  chmod 0600 "$HARDEN_DROPIN"

  sshd -t
  systemctl reload sshd || systemctl restart sshd
}

imds() {
  local path="$1" token
  token="$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300")" || return 1
  curl -sf -H "X-aws-ec2-metadata-token: ${token}" \
    "http://169.254.169.254/latest/meta-data/${path}"
}

configure_from_tags() {
  local iid region name
  iid="$(imds instance-id)" || { log WARN "IMDS unavailable, skipping tag config"; return 0; }
  region="$(imds placement/region)" || return 0

  name="$(aws ec2 describe-tags --region "$region" \
    --filters "Name=resource-id,Values=${iid}" "Name=key,Values=Name" \
    --query 'Tags[0].Value' --output text 2>/dev/null || echo None)"

  if [[ -n "$name" && "$name" != "None" ]]; then
    log INFO "setting hostname to ${name}"
    hostnamectl set-hostname "$name"
  else
    log INFO "no Name tag found, leaving hostname unchanged"
  fi
}

main() {
  [[ "$(id -u)" -eq 0 ]] || die "must run as root"
  update_packages
  install_agents
  harden_ssh
  configure_from_tags
  log INFO "bootstrap complete"
}

main "$@"
