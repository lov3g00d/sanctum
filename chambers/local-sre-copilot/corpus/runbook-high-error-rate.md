# Runbook: High HTTP 5xx error rate

## Symptom
A service is returning an elevated rate of HTTP 5xx responses. Alert
`ErrorBudgetBurnFast` (burn rate > 14.4x) or `HighErrorRate` has fired.

## Severity
- Burn rate > 14.4x over 5m and 1h windows: SEV2 (page on-call).
- Burn rate > 6x: SEV3 (ticket).

## Diagnose
1. Confirm the error rate in Prometheus:
   `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))`
2. Find which route/version is failing: break the query down by `route` and
   `version` labels.
3. Check recent deploys: a spike right after a rollout points at the new version.
4. Pull the error logs for the failing route from the logging backend and look
   for a common error signature (stack trace, dependency timeout, 500 body).

## Common causes and fixes
- **Bad deploy / new version**: roll back or shift traffic away from the new
  version. For a canary, set the weight back to 0 (blue-green flip to the last
  good version).
- **Downstream dependency failing** (DB, upstream API): the app errors because a
  dependency is down. Fix or fail over the dependency; consider enabling the
  circuit breaker so the app sheds load instead of piling onto the dependency.
- **Resource exhaustion** (OOM, CPU throttling): check pod restarts and limits;
  scale up or raise limits.

## Mitigate
- Roll back the last deploy if it correlates with the spike.
- If a single version is bad, set its traffic weight to 0.
- If a dependency is down, enable degraded mode / circuit breaking.

## Verify recovery
Error ratio drops below the SLO threshold and the burn-rate alert clears.
