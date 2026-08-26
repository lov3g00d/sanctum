# Platform architecture (reference)

## Services
- **checkout**: user-facing web service. Behind a load balancer, deployed as
  v1/v2 with weighted routing for canary and blue-green releases.
- **payments**: dependency of checkout. Talks to the payments database over a
  fixed-size connection pool.
- **payments-db**: PostgreSQL. Connection pool size is the usual saturation point.

## Observability
- **Metrics**: Prometheus scrapes `http_requests_total` and
  `http_request_duration_seconds` from every service. SLOs are recorded rules;
  multi-window burn-rate alerts page at 14.4x and ticket at 6x.
- **Logs**: structured logs shipped to a central store, queryable by service,
  level, and status.
- **Checks**: an Icinga host/service check hits each service's `/healthz`.

## Release model
- Canary: shift a small traffic weight to the new version, watch, ramp.
- Blue-green: both versions deployed; flip 100% in one step; roll back by
  flipping the weight back. Rollback is a one-line traffic-weight change, not a
  redeploy.

## Golden rules
- A spike right after a deploy is a deploy problem until proven otherwise.
- Roll back first, investigate second.
- Prefer traffic-weight flips over redeploys for fast rollback.
