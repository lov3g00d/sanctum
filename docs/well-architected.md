# AWS Well-Architected, mapped to Nimbus

The Well-Architected Framework is six pillars plus a review process. In an interview
the trap is reciting the pillar names. The signal is showing you make explicit
tradeoffs between them, because they conflict: more reliability costs money, more
security adds latency, more performance can hurt cost. Below each pillar lists the
design questions it asks, what Nimbus does about it, and where in this repo.

## 1. Operational Excellence

"Can you run, observe, and improve the system safely?"

- Everything is code: infra in `terraform/`, app config in `kubernetes/`, pipelines in `cicd/`. No console clicks that drift from source of truth.
- Small, frequent, reversible changes: CI gates + `kubectl rollout` with automatic halt on failed readiness, `rollout undo` for rollback.
- Observability before features: `monitoring/` ships dashboards, SLOs, and runbook links from day one.
- Game days / failure injection belong here (chaos testing pods and AZ loss).

## 2. Security

"Least privilege, everywhere, verifiable."

- Identity: no long-lived AWS keys. CI authenticates with GitHub OIDC (`terraform/modules/github-oidc/`), workloads use IRSA per service account. This is the single highest-leverage AWS security control.
- Network: default-deny NetworkPolicy in `kubernetes/security/`, private subnets for compute and data, security groups referencing other SGs rather than CIDRs.
- Data: KMS encryption at rest on RDS/S3/EKS secrets, TLS in transit, secrets in Secrets Manager/SSM, never in Git (`.gitignore` + gitleaks).
- Edge: Cloudflare WAF, rate limiting, and authenticated origin pulls so the AWS origin only trusts Cloudflare.
- The whole `cicd/` security-gate chain is this pillar shifted left. See [`devsecops-shift-left.md`](devsecops-shift-left.md).

## 3. Reliability

"Does it recover automatically, and do you know your limits?"

- Multi-AZ everywhere: subnets across 3 AZs, RDS Multi-AZ standby, pods spread with `topologySpreadConstraints`.
- Self-healing: liveness/readiness probes, HPA, Karpenter node replacement, PodDisruptionBudgets so voluntary disruptions never take the service below quorum.
- Defined limits: SLOs and error budgets in `monitoring/`, backup/restore with stated RTO/RPO in [`resilience-auto-recovery.md`](resilience-auto-recovery.md).
- Quotas and limits are a reliability control too (`ResourceQuota`/`LimitRange`), they stop one workload starving the cluster.

## 4. Performance Efficiency

"Right resource, right size, and you measured it."

- Compute split by workload shape: always-on core on EKS, spiky/event-driven on Lambda (`terraform/modules/serverless-api/`). Paying for idle EKS capacity to serve rare endpoints is the anti-pattern this avoids.
- Caching at two layers: Cloudflare CDN at the edge, ElastiCache Redis for hot data.
- Autoscaling on real signals: HPA on CPU and memory (and custom metrics in reality), Karpenter provisioning right-sized nodes including spot.
- Right-sizing is driven by the saturation metrics in `monitoring/`, not guesses.

## 5. Cost Optimization

"Are you paying only for what you need, and can you see it?"

- Serverless for low/spiky traffic (pay per request, scale to zero).
- Karpenter with spot instances for stateless workloads, on-demand for stateful.
- Environment asymmetry: `dev` runs a single NAT gateway and single-AZ RDS; `prod` runs NAT-per-AZ and Multi-AZ. NAT gateways and cross-AZ data transfer are common surprise line items.
- Cost is a first-class signal: tag everything (`Project`, `Environment`, `Owner`) so spend is attributable, then alert on anomalies.

## 6. Sustainability

"Minimize the resources and energy per unit of work."

- Scale-to-zero serverless, spot capacity reclaiming idle hardware, right-sizing, and Graviton (arm64) as the default instance family where the image supports it. Largely the same actions as cost optimization, measured against carbon rather than dollars.

## The review process (the part people forget)

Well-Architected is not a one-time checklist. AWS ships the Well-Architected Tool
and Trusted Advisor to run periodic reviews that surface high-risk issues (HRIs)
against the pillars. Saying "we run a quarterly WA review and track the HRIs as
backlog items" signals you have operated it, not just read it.

## The tradeoff sentence to have ready

> "The pillars conflict, so we optimize for the business constraint. For a B2B
> platform launching now, I bias to reliability and security first, keep cost
> controlled with serverless and spot for the parts that tolerate it, and treat
> performance tuning as data-driven follow-up once we can see the saturation signals."
