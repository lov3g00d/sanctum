# Chamber: kind-icinga

Icinga on kind: the classic **check-and-notify** monitoring stack (Icinga 2 +
Icinga DB + Icinga Web 2) watching a sample HTTP service. Define a host and a
service check, break the app, and watch Icinga drive the check to a HARD
CRITICAL and fire a notification, then heal it and watch the recovery. The
deliberate counterpart to the pull-model Prometheus setup in
[`kind-slo-error-budget`](../kind-slo-error-budget/).

## Stack

kind + the official `icinga-stack` Helm chart. Icinga 2 is the check scheduler
and notification engine; Icinga DB (a Redis relay plus MariaDB) is the state
backend; Icinga Web 2 is the UI. A Flask app with a health toggle is the
monitored target. The monitoring config (a `Host`, a `Service` running the
`check_http` plugin, a `TimePeriod`, a `User`, and a `Notification`) is pushed to
Icinga 2 through its REST API as a config package.

The full stack is enabled: the Director config module and the
Icinga-for-Kubernetes collector (a daemon that syncs cluster state into Icinga)
run alongside the core. The chart's collector image tag is pinned to a published
version in `values.yaml` (its default points at a tag that was never released),
and all component images stay on the chart's tested versions rather than
`latest`, which pulls a newer Icinga 2 the chart's bootstrap does not support.

## Prerequisites

`nix develop` from the repo root (provides `kind`, `kubectl`, `helm`, `task`,
`python`) and a running Docker.

## Use

```sh
cd chambers/kind-icinga
task up          # kind + Icinga stack + app + monitoring config
task status      # current check states, read from the Icinga 2 API
task check-demo  # OK -> break to HARD CRITICAL + notification -> heal to recovery
task break       # make the app return HTTP 500 on /healthz
task heal        # make the app healthy again
task apply       # re-push the monitoring config after editing icinga/monitoring.conf
task down        # delete the kind cluster
```

Icinga Web 2: http://localhost:18082 (icingaadmin/icinga). Browse Hosts and
Services, watch a check flip to CRITICAL, and see the notification history.

## What it demonstrates

- **The check-and-notify model**: Icinga 2 actively runs a plugin on a schedule,
  classifies the result (OK/WARNING/CRITICAL/UNKNOWN), and notifies on state
  change. This is the opposite of Prometheus, which pulls metrics and evaluates
  alert rules over a time series.
- **Soft vs hard states**: a failing check is SOFT until `max_check_attempts` is
  reached, then HARD; notifications fire on the HARD transition, not the first
  blip.
- **Objects and apply rules**: `Host`, `Service`, `CheckCommand`, `TimePeriod`,
  `User`, and an `apply Notification ... to Service` rule, all as declarative
  config.
- **The Nagios plugin API**: `check_http` returns an exit code (0/1/2/3) and
  performance data; that exit code is the service state.
- **Config as code through the API**: the chart disables `conf.d`, so config is
  delivered as an Icinga 2 REST API config package rather than files on disk.
- **Icinga DB architecture**: Icinga 2 writes state to Redis, the Icinga DB
  daemon persists it to MariaDB, and Icinga Web 2 reads from there.

## Reference

[`icinga.md`](icinga.md) is a deep-dive on how Icinga works end to end (the two
planes, the check pipeline, soft/hard states, the object model, Icinga DB, config
delivery, notifications, and how it contrasts with Prometheus), grounded in this
chamber. [`icinga-architecture.html`](icinga-architecture.html) is a
self-contained visual reference to the same material (open it in a browser).
