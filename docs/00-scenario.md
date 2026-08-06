# Scenario: the Nimbus B2B platform

Everything in this repo describes one fictional but realistic system, **Nimbus**: a
B2B API platform that other businesses integrate with. Having a single scenario is
deliberate. In an interview you can walk the whole stack as one story instead of
reciting disconnected facts, and every file here is a concrete thing you can point at.

## Business context

- B2B, so traffic is bursty and integration-driven: partners call our REST APIs,
  we call theirs, and a bad deploy or outage is visible to paying customers immediately.
- Launching in 2025, so the design favours things that are cheap to run small and
  scale without re-architecture (managed data stores, autoscaling, spot capacity).
- Security is a first-class requirement (this is a DevSecOps role, not just DevOps):
  controls live in the pipeline and the platform, not in a wiki nobody reads.

## Fixed conventions (used by every directory in this repo)

| Thing | Value |
|-------|-------|
| Platform codename | `nimbus` |
| Primary region | `eu-central-1` (Frankfurt) |
| DR region | `eu-west-1` (Ireland) |
| Environments | `dev`, `prod` |
| Workload | `podinfo` (upstream `stefanprodan/podinfo`, Go, port 9898) |
| Public hostname | `api.nimbus.example.com` |
| Kubernetes namespace | `nimbus` |
| Observability namespace | `monitoring` |
| Registry | ECR: `<acct>.dkr.ecr.eu-central-1.amazonaws.com/nimbus/<svc>` |
| IaC state | S3 bucket `nimbus-tfstate-<acct>`, S3-native locking (`use_lockfile`) |
| Standard tags | `Project=nimbus`, `Environment`, `ManagedBy=terraform`, `Owner=platform-team` |

## Request path (edge to data)

```
                Internet (partners, clients)
                          │
                          ▼
             ┌─────────────────────────────┐
             │  Cloudflare                 │  DNS, WAF, DDoS, CDN, TLS,
             │  (edge, outside AWS)        │  rate limiting, bot mgmt
             └──────────────┬──────────────┘
                            │  (authenticated origin pull / mTLS)
                            ▼
             ┌─────────────────────────────┐
             │  AWS  eu-central-1          │
             │                             │
   public →  │   ALB (WAF assoc.)          │
   subnets   │        │                    │
             │        ▼                    │
   private → │   EKS  (podinfo)            │
   subnets   │   HPA + Karpenter, IRSA     │
             │        │                    │
   data    → │   RDS PostgreSQL (Multi-AZ) │   ElastiCache Redis   S3
   subnets   │   encrypted, PITR backups   │   (sessions/cache)    (objects)
             └─────────────────────────────┘
```

EKS is the compute plane. `podinfo` (a public cloud-native test app) stands in for
the core service so the platform can be exercised end to end without shipping
bespoke app code. Kubernetes gives us rolling deploys, self-healing (failed
pods/nodes are replaced), horizontal autoscaling, and a portable place to enforce
network policy and pod security.

Cloudflare sits in front. It absorbs DDoS and bad traffic before it costs us
anything, terminates TLS at the edge, and gives us a WAF and rate limiting that
protect the origin regardless of what runs behind it.

## How resilience / auto-recovery is achieved (the job's headline ask)

| Failure | What recovers it | Manual steps |
|---------|-----------------|--------------|
| Pod crashes | Kubernetes restarts it (liveness probe) | none |
| Node dies | ASG/Karpenter replaces it, pods reschedule | none |
| AZ outage | Multi-AZ subnets + RDS Multi-AZ failover | none |
| Traffic spike | HPA scales pods, Karpenter adds nodes | none |
| Bad deploy | Rolling update halts on failed readiness; ArgoCD can auto-rollback | none / one click |
| Region outage | Restore from cross-region backups in `eu-west-1` (documented RTO/RPO) | runbook |

Details and the numbers (RTO/RPO, health-check tuning) live in
[`resilience-auto-recovery.md`](resilience-auto-recovery.md).

## Where each job qualification is demonstrated

| Qualification | Where in this repo |
|---------------|--------------------|
| AWS + Well-Architected | `terraform/`, [`well-architected.md`](well-architected.md) |
| Terraform IaC | `terraform/` (modules + `live/` Terragrunt + remote state) |
| Kubernetes + Docker | `charts/podinfo/`, `terraform/modules/platform/policies/`, `docker/` |
| Cloudflare | `terraform/modules/cloudflare/` |
| Monitoring / Grafana | `terraform/modules/platform/config/`, `charts/podinfo/` |
| Linux + Bash | `scripts/` |
| Nginx / container workload | `docker/nginx/`, `docker/podinfo.Dockerfile` |
| Networking (TCP/IP, DNS, HTTP) | [`networking-fundamentals.md`](networking-fundamentals.md) |
| Security in the SDLC | `cicd/`, [`devsecops-shift-left.md`](devsecops-shift-left.md) |
| Root-cause / troubleshooting | [`interview-cheatsheet.md`](interview-cheatsheet.md) |
