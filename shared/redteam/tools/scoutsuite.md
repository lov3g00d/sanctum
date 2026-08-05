# ScoutSuite - multi-service AWS CSPM enumeration

ScoutSuite (NCC Group) enumerates an AWS account across every service and emits
an offline HTML report ranked by severity. It covers the same ground as the
scheduled Prowler run
(`chambers/aws-eks/terraform/modules/platform/policies/cspm/prowler-cronjob.yaml`) but from the
assessor's side: an on-demand, browsable snapshot of account posture for a
point-in-time review, rather than a benchmark-scored CronJob shipping findings to
S3.

Use it alongside Prowler, not instead of it. Prowler gives you CIS/SOC2/PCI
compliance scoring on a weekly cadence; ScoutSuite gives you a fast, visual,
cross-service sweep when you want to eyeball the whole account at once.

## Scope and authorization

- Target: the operator's OWN sandbox AWS account `123456789012`, nothing else.
- Credentials: the read-only `SecurityAudit` + `ViewOnlyAccess` identity used by
  the CSPM tooling. ScoutSuite is read-only by design (it only calls `Describe*`,
  `List*`, and `Get*`), so no write access is needed or wanted.
- Do not run it against an account you do not own.

## Run it in a container

Inject read-only credentials from the environment; prefer short-lived STS
credentials from an assumed role over static keys.

```
docker run --rm -it \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e AWS_DEFAULT_REGION=eu-central-1 \
  -v "$(pwd)/scoutsuite-report:/opt/scoutsuite-report" \
  rossja/ncc-scoutsuite:latest \
  scout aws \
    --report-dir /opt/scoutsuite-report \
    --no-browser
```

`--no-browser` keeps it headless (it otherwise tries to open the report); the
HTML report lands in `./scoutsuite-report`. Open `report.html` locally to browse
findings by service and severity.

To narrow a run, add `--services iam s3 ec2 vpc` and scope regions with
`--regions eu-central-1`.

## Reading the result

Work the report highest-severity first. For this platform the findings that
matter most map back to controls that already exist in `terraform/`:

- IAM: no wildcard policies, no unused credentials, MFA on any human user.
- S3: no public buckets, encryption and TLS-only policies enforced.
- VPC / security groups: no `0.0.0.0/0` ingress to sensitive ports.
- Logging: CloudTrail enabled, multi-region, log-file validation on.

A finding here is a Terraform fix, not a manual console change: correct it in the
module so the fix ships through the gated pipeline, then confirm both ScoutSuite
and the next Prowler run come back clean. Left is cheaper than right - a drift
ScoutSuite catches by hand should also be caught by the weekly Prowler CronJob
and by checkov/trivy on the IaC in CI.
