# Interview cheatsheet - Senior DevSecOps, Bet On Talent

Read this last. It assumes you know the material and just need it loaded into fast
memory: how to frame your own experience against this JD, the two honest gaps and how
to handle them, and rapid-fire answers per topic.

Role: Senior DevSecOps Engineer, remote Europe, B2B platform launching 2025, reports
to a DevOps Lead. Emphasis: security in the SDLC, AWS + Cloudflare IaC, CI/CD for
production, monitoring/alerting, and self-healing/auto-recovery.

## 1. Frame your experience against their asks

You are over the bar on most of this. The job is to translate, not to impress with
volume. Lead with the story that matches each ask.

| They want | Your proof (from your track record) |
|-----------|-------------------------------------|
| 3+ yrs AWS, HA/scalable | Platonic: multi-account AWS (dev/test/prod/internal-ops), EKS, VPC, IAM, Route 53, ElastiCache, Secrets Manager, Client VPN, ECS/Fargate |
| IaC with Terraform | Terraform/Terragrunt across both Platonic and Myle; HashiCorp Terraform Associate exam prep |
| CI/CD for prod deploys | GitHub Actions with OIDC federation + self-hosted EC2 runners (Platonic); GitLab CI/CD legacy-to-automated at Syniverse |
| Monitoring/alerting (Grafana) | Prometheus, Grafana, Loki, Vector observability stack (Platonic); centralized logging (Myle) |
| Kubernetes + Docker | EKS/GKE, Argo CD app-of-apps, Helm/Helmfile, Karpenter, Traefik, cert-manager, external-secrets |
| Resilient/self-healing | Karpenter spot autoscaling, Velero backup/restore, zero-downtime cross-account signing-service migration |
| DevSecOps / security | Hands-on security assessments, vuln scanning, policy enforcement across CI/CD and K8s; pentest background |
| Linux + Bash + Python | Python/Bash automation across both fintech and ride-hailing platforms |
| Node.js / Nginx | Dockerized Node.js services at Myle; Traefik/Nginx-class reverse proxying |
| Cost / FinOps | Myle: cut cloud spend up to 50% while improving stability and compliance |
| Cross-department comms | You bridged app, test, and platform teams at Syniverse and Myle |

Headline lines to have ready:
- "I cut cloud spend up to 50% at Myle while tightening security and compliance, so I treat cost as an engineering signal, not an afterthought."
- "At Platonic I ran a zero-downtime cross-account migration of a signing service, which is exactly the fail-safe, no-manual-intervention mindset this role is about."
- "I moved a fully manual telecom release process to automated CI/CD at Syniverse, so I have taken an org from zero pipelines to production automation."

## 2. The two honest gaps (prepare these, do not get caught)

**AWS Associate certification.** The JD says "ideally at least one Associate-level AWS
cert." You have HashiCorp Terraform Associate prep and a stack of Google Cloud/SRE
courses, not an AWS badge. Do not bluff.
> "I do not hold an AWS Associate cert yet; my AWS depth is from operating multi-account
> production platforms rather than exam prep. I have the Terraform Associate track done
> and I am comfortable committing to Solutions Architect or SysOps Associate in my first
> quarter if that matters for the team."
Also skim: the Well-Architected pillars (see `well-architected.md`), the difference
between SGs and NACLs, IAM roles vs users, S3 storage classes, and the AZ/Region model.
These are the SAA staples that come up as questions even without the badge.

**Cloudflare.** Not on your CV. You know the concepts cold from Traefik, Nginx, HAProxy,
cert-manager, and edge/CDN work, so frame it as vocabulary, not a new domain.
> "I have not run Cloudflare specifically, but I have run the same functions with
> Traefik and Nginx at the edge: TLS termination, WAF, rate limiting, reverse proxy.
> Cloudflare is those functions as a managed anycast layer plus DNS and DDoS."
Know for Cloudflare specifically: proxied vs DNS-only (orange vs grey cloud), SSL modes
(off/flexible/full/full-strict, and why full-strict), authenticated origin pulls,
WAF managed rules + custom rate-limiting rules, Workers (edge compute), the fact that
proxied records hide your origin IP. `terraform/modules/cloudflare/` shows it as IaC.

**Serverless / Lambda.** You list serverless and ECS/Fargate but not Lambda by name.
Know: Lambda execution model (cold start, concurrency, reserved vs provisioned), API
Gateway (REST vs HTTP API), event sources, when serverless beats containers (spiky,
low, event-driven) and when it does not (steady high throughput, long-running, heavy
local state). This repo is EKS-centric, so speak to serverless as a design tradeoff
you reach for when the workload shape fits, not as something wired up here.

## 3. Rapid-fire by topic

**AWS / Well-Architected**
- Six pillars: operational excellence, security, reliability, performance efficiency, cost optimization, sustainability. They conflict; you optimize for the business constraint.
- IAM role vs user: roles are assumed and give temporary credentials, no long-lived secret. Prefer roles + federation everywhere.
- Region vs AZ: a Region is a geography, an AZ is an isolated datacenter group within it. Multi-AZ for HA, multi-Region for DR.

**Terraform**
- State is the source of truth for what exists; remote state in S3 + DynamoDB lock so concurrent applies do not corrupt it.
- Modules for reuse, directories per environment for isolation (blast radius), pinned provider versions for reproducibility.
- `plan` before `apply`, always. `terraform import` for adopting existing resources. Avoid `-target` except in emergencies. Never store secrets in state you can avoid; mark outputs sensitive.
- Terragrunt (which you have used) is for keeping many environments DRY and wiring remote state/backends without copy-paste.

**Kubernetes**
- Self-healing: controllers reconcile actual state to desired state; that reconciliation loop is the whole point.
- Probes: liveness restarts, readiness de-registers, startup guards slow boot. Liveness must not depend on external services.
- Requests vs limits: requests drive scheduling, limits cap usage; CPU throttles, memory OOM-kills.
- HPA scales pods on metrics, Cluster Autoscaler/Karpenter scales nodes, PDB protects availability during disruptions.
- Security: Pod Security Admission restricted, non-root read-only containers, NetworkPolicy default-deny, RBAC least-privilege, IRSA for AWS access.

**Docker**
- Multistage build to keep build tools out of the runtime image; distroless/minimal base to shrink attack surface; non-root user; pin base by digest; one process per container; HEALTHCHECK.
- Layer caching: order Dockerfile from least to most frequently changing (deps before source).

**CI/CD + DevSecOps** (this is the differentiator, go deep, see `devsecops-shift-left.md`)
- Shift left: SAST (source), SCA (deps), secret scan, IaC scan, image scan, DAST (running app). All fail-closed in CI.
- Supply chain: SBOM (syft) + sign (cosign) + verify at admission (Kyverno). SLSA provenance.
- OIDC over long-lived keys: CI assumes a role via short-lived tokens, nothing to leak. You have done exactly this at Platonic.

**Monitoring** (see `monitoring/`)
- Four golden signals: latency, traffic, errors, saturation. RED for services, USE for resources.
- SLI/SLO/error budget: the SLO sets how much unreliability is acceptable; the error budget is what you spend on releases; multi-window multi-burn-rate alerts page only when the budget is genuinely at risk.
- Alert on symptoms (user-visible), not causes. Reduce alert fatigue or you train people to ignore pages.

**Networking** (see `networking-fundamentals.md`)
- TCP 3-way handshake, TLS 1.3 1-RTT, DNS resolution chain, HTTP/2 vs 3, 502 vs 503 vs 504.
- SG (stateful, instance) vs NACL (stateless, subnet). Public vs private vs data subnet tiers, NAT for egress.

**Resilience** (see `resilience-auto-recovery.md`)
- RTO (how long to recover) vs RPO (how much data lost). DR spectrum: backup-restore, pilot light, warm standby, active-active.
- Cascading-failure controls: timeouts, backoff+jitter, circuit breakers, graceful degradation, load shedding.
- Deploy safety: rolling (readiness-gated), blue-green, canary with automated rollback on SLO burn.

**Linux / Bash**
- Strict mode: `set -euo pipefail`, quote expansions, trap for cleanup. `scripts/` shows the pattern.
- Debugging: `top`/`htop`, `ss`, `dig`, `journalctl`, `strace`, `/proc`, `dmesg`. Load average vs CPU%, memory vs cache, disk vs inode exhaustion.

## 4. Behavioral: cross-department communication

The JD calls this out explicitly ("key point of communication across departments").
Have one concrete story: you bridged application, test, and platform teams (Syniverse,
Myle) and translated between engineering and non-engineering stakeholders. The point
they want: you can explain an incident or a tradeoff to a product owner without jargon,
and you turn their constraints into technical requirements.

Incident/root-cause story (they value "tracing issues back to root cause"): pick one
real debugging story, structure it as symptom, hypothesis, how you bisected the path,
the actual root cause, and the systemic fix (not just the patch). Your BFT blockchain
and cross-account migration work are rich sources.

## 5. Questions to ask them (signals seniority)

- What does the on-call rotation and incident process look like today, and what is the current biggest source of pages?
- Where are you on the DevSecOps maturity curve: what security gates already run in CI, and what is still manual?
- What are the current SLOs, and who owns the error budget?
- The platform launches in 2025; what is the expected traffic shape and the top reliability risk you are hiring this role to reduce?
- How is the AWS/Cloudflare split decided today, and is there appetite for Karpenter/spot and serverless where they fit?
- What does the first 90 days look like as success for this role?

## 6. Final calibration

- You are an architect interviewing for a senior IC role; show depth without taking over. Answer the question asked, then offer one layer deeper.
- When you do not know something, say so and bridge to the nearest thing you have done. You have enough real depth that honesty reads as confidence, not weakness.
- Every claim in this repo is something you can open and walk through. If a topic comes up, you have a file to point at.
