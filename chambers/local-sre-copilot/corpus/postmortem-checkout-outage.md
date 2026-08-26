# Postmortem: Checkout 500s after payments deploy (2026-05-14)

## Summary
For 38 minutes the checkout service returned HTTP 500 for ~40% of requests after
a routine deploy of the payments dependency. Root cause was a database
connection-pool exhaustion in payments triggered by a new synchronous call path.
Blameless.

## Impact
- 38 minutes of degraded checkout (SEV2).
- ~12,000 failed checkout attempts, error budget for the month reduced by 22%.

## Timeline (UTC)
- 14:02 payments v2.7.0 deployed (canary at 10%, then ramped to 100% by 14:09).
- 14:11 `ErrorBudgetBurnFast` fired for checkout (burn rate 18x).
- 14:14 on-call paged, began triage.
- 14:20 identified the spike began right after payments reached 100%.
- 14:28 payments error logs showed `connection pool exhausted` and timeouts.
- 14:33 rolled payments back to v2.6.4 (flipped traffic weight to the old
  version).
- 14:41 error rate recovered, alert cleared.

## Root cause
payments v2.7.0 added a synchronous call to a fraud-scoring service inside the
request path, holding a database connection for the duration. Under load the
fixed-size connection pool was exhausted, so checkout requests to payments timed
out and surfaced as 500s.

## What went well
- The burn-rate alert fired fast and accurately.
- Rollback by traffic-weight flip was a one-line change and instant.

## What went wrong
- The canary ramp was too fast (7 minutes) to catch a load-dependent failure.
- No pool-saturation metric was alerted on.

## Action items
- Slow the default canary ramp and add a bake time.
- Alert on database connection-pool saturation in payments.
- Move fraud scoring off the synchronous request path.
