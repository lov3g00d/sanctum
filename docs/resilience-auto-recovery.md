# Resilience and automatic recovery

This is the job's headline: "fail safely, recover automatically, keep the business
running with minimal to no manual intervention." Resilience is not one feature, it is
a property you get by handling each failure domain with a mechanism that acts without
a human. This doc lists the failure domains, the mechanism that recovers each, and the
numbers (RTO/RPO) you should be able to state.

## Failure domains and their automatic recovery

| Failure | Detection | Recovery mechanism | Human action |
|---------|-----------|--------------------|--------------|
| Process hang/crash | liveness probe fails | kubelet restarts the container | none |
| Pod unhealthy but alive | readiness probe fails | pulled from Service endpoints, traffic reroutes | none |
| Node failure | node NotReady | pods rescheduled, Karpenter/ASG replaces the node | none |
| AZ outage | health checks across AZ fail | Multi-AZ subnets keep 2/3 alive, RDS fails over to standby | none |
| Traffic spike | CPU/latency rises | HPA adds pods, Karpenter adds nodes | none |
| Bad deploy | readiness never goes green | rolling update stalls, keeps old pods serving; auto-rollback | none / approve |
| Dependency slow/down | timeout + circuit breaker | shed load, serve degraded, stop the cascade | none |
| Region outage | regional health check | restore in `eu-west-1` from cross-region backups | runbook |
| Data corruption / bad write | alerts, user reports | point-in-time restore to just before the event | runbook |

The pattern: most rows are "none." Region loss and data corruption are the two that
justify a runbook, because automating a full regional failover has its own failure
modes and a launching platform rarely needs sub-minute regional RTO on day one.

## Health checks, the part people get wrong

Three probe types, different jobs:

- **startupProbe**: guards slow-starting apps. Until it passes, liveness/readiness are suspended, so a slow boot is not mistaken for a crash loop.
- **livenessProbe**: "is the process wedged?" Failure restarts the container. Keep it cheap and dependency-free. A liveness probe that checks the database will restart every pod when the database blips, turning a data-layer issue into a full outage. This is the single most common self-inflicted incident.
- **readinessProbe**: "can it serve right now?" Failure removes the pod from the Service without killing it. This one checks dependencies, and it is what makes rolling deploys safe and load-shedding possible.

Nimbus exposes `/healthz` (liveness, always 200 while the process is up) and `/readyz`
(readiness, 503 when a dependency is down), which is exactly the split above.

## High availability by design

- **Redundancy with no shared fate:** N+1 or better, spread across AZs with `topologySpreadConstraints`, so losing one AZ loses a fraction, not the service.
- **PodDisruptionBudget:** caps voluntary disruptions (node drains, upgrades) so a cluster operation never takes you below quorum.
- **Stateless app tier:** the orders API keeps no local state, so any pod can serve any request and replacement is free. State lives in RDS/Redis/S3, which have their own HA.
- **RDS Multi-AZ:** a synchronous standby in another AZ; failover is automatic and takes tens of seconds, DNS endpoint stays the same so the app reconnects without config change.

## Backups, RTO, and RPO (know the definitions cold)

- **RPO (Recovery Point Objective):** how much data you can afford to lose, measured in time. Set by backup frequency. RDS automated backups + transaction logs give near-continuous PITR, so RPO is on the order of minutes.
- **RTO (Recovery Time Objective):** how long recovery may take. Set by the restore mechanism.

Nimbus targets (illustrative, the point is to have numbers and defend them):

| Scenario | RPO | RTO | How |
|----------|-----|-----|-----|
| AZ loss | 0 | seconds | Multi-AZ standby failover |
| Accidental bad write | ~5 min | ~30 min | RDS point-in-time restore |
| Region loss | ~15 min | ~2-4 h | restore from cross-region backup copy in eu-west-1 |

`scripts/backup-postgres.sh` shows the logical-backup path (pg_dump to encrypted S3
with retention), which complements RDS snapshots for portability and long retention.

## DR strategy spectrum (name the tradeoff)

From cheapest/slowest to priciest/fastest:

1. **Backup and restore** - restore infra + data in the DR region on demand. Hours of RTO, lowest cost. Nimbus's day-one posture.
2. **Pilot light** - core data replicated and minimal infra always on, scale up on failover. Tens of minutes.
3. **Warm standby** - a scaled-down full copy running, scale up on failover. Minutes.
4. **Multi-region active-active** - full capacity both regions, no failover step. Seconds, highest cost and complexity (data consistency across regions is the hard part).

The senior answer is not "always active-active." It is "match the DR tier to the
business RTO/RPO and cost tolerance, and revisit as the platform grows."

## Stopping cascading failure

Recovery is not only about restarting things, it is about failing without spreading:

- **Timeouts** on every network call, with a budget that shrinks down the call chain.
- **Retries with exponential backoff and jitter**, capped, only for idempotent operations, so a blip does not become a retry storm.
- **Circuit breakers**: after N failures, stop calling the sick dependency, fail fast, and probe periodically to recover.
- **Graceful degradation**: serve cached or reduced responses when a non-critical dependency is down rather than erroring the whole request.
- **Bulkheads / load shedding**: isolate resource pools and drop excess load (429) so overload in one area does not sink the rest.

## Safe deployments (recovery from your own changes)

- **Rolling update** (default): readiness-gated, so a broken version never receives traffic and the rollout halts itself.
- **Blue-green**: full parallel environment, flip traffic, instant rollback by flipping back.
- **Canary**: shift a small traffic slice to the new version, watch the SLO burn rate in the kube-prometheus-stack, promote or roll back automatically. Argo Rollouts / Flagger drive this.
- **Automated rollback**: tie the deploy to the error-budget burn alert, a spike auto-triggers `kubectl rollout undo`.

## Verifying resilience (do not assume it)

Chaos engineering: deliberately kill pods, cordon nodes, inject latency, and simulate
an AZ loss in a game day, then confirm the automatic mechanisms above actually fire
and the SLO holds. Resilience you have not tested is a hypothesis.
