# GitOps: application delivery for podinfo

ArgoCD reconciles the Kustomize manifests under `kubernetes/` into the cluster.
This directory holds the day-2 delivery CRs it acts on: the project that scopes
what may be synced, the ApplicationSet that turns each overlay into an
Application, and an optional Argo Rollouts example that gates promotion on the
service's SLO.

## Day 1 vs day 2

The two halves are deliberately owned by different layers so a bad app change
cannot reach into the platform.

- **Day 1, platform.** The Terraform platform module installs ArgoCD itself
  (`helm_release`, namespace `argocd`). ArgoCD is infrastructure: it is created
  and upgraded the same way as the cluster, IRSA, and the ingress controller.
  Nothing in this directory installs ArgoCD.
- **Day 2, this layer.** Once ArgoCD is running it needs to be told what to
  deliver. These are the application-delivery custom resources it reconciles:
  `AppProject`, `ApplicationSet`, and (opt-in) `Rollout` + `AnalysisTemplate`.

Bootstrapping is a single apply of `gitops/` (project + ApplicationSet); from
there ArgoCD manages the rest from git.

## ApplicationSet vs app-of-apps

The classic pattern is app-of-apps: one parent Application whose manifests are a
folder of hand-written child `Application` objects, one per env. It works, but
every new environment is a new file to author and keep in sync, and drift
between those near-identical files is where mistakes hide. (A prior platform in
this org runs ~75 hand-written Applications and zero ApplicationSets; that is the
maintenance cost this layer is built to avoid.)

An [ApplicationSet](applicationset.yaml) replaces the folder of copies with a
generator plus one template. The git **directory generator** globs
`kubernetes/overlays/*` and emits one element per matching directory;
`{{path.basename}}` is the leaf name (`dev`, `prod`). Each element renders the
template into an Application named `podinfo-<env>` whose `source.path`
is that overlay. Add `kubernetes/overlays/staging/` and a staging Application
appears on the next reconcile with no edit here. One template is the single
place a delivery-policy change (sync options, project, destination) lands.

Sync policy is `automated` with `prune` and `selfHeal`, plus
`CreateNamespace=true`, so a deleted resource is restored and a removed overlay
is pruned without a human in the loop.

### One cluster, one destination: read this before applying

The generated `podinfo-dev` and `podinfo-prod` both target
`https://kubernetes.default.svc` and namespace `nimbus`, because both overlays
set that namespace and the `nimbus` AppProject exposes a single in-cluster
destination. Applied to **one** cluster they would fight over the same resource
names. That is intentional for a single-cluster practice repo that shows
per-overlay Application generation. Real multi-env delivery keeps the envs apart
by pairing the git generator with a **cluster generator** in a matrix, so each
overlay lands on its own cluster (or its own namespace). That composition, one
generator feeding another, is the second reason ApplicationSets win over
app-of-apps: the fan-out is declarative, not copy-paste.

## SLO-gated canary (Argo Rollouts)

`rollouts/` is an opt-in progressive-delivery example. A
[Rollout](rollouts/podinfo-rollout.yaml) **replaces** the Deployment (you
drop `deployment.yaml` from the overlay and reconcile the Rollout instead); the
podSpec mirrors the hardened Deployment so the non-root, read-only-rootfs,
drop-ALL-caps, probe-on-`/healthz`-and-`/readyz` posture is unchanged.

The canary advances in steps: `setWeight: 20` -> `pause 5m` -> **analysis** ->
`setWeight: 50` -> **analysis** -> `setWeight: 100`. The pause lets canary
traffic accumulate so the 5-minute-rate recording rules have a real window to
measure before the first gate.

Each analysis runs the [AnalysisTemplate](rollouts/analysistemplate-slo.yaml),
which queries Prometheus at
`http://kube-prometheus-stack-prometheus.monitoring:9090` for two precomputed
recording rules, scoped to `{namespace="nimbus"}` so each returns a single
series:

- `slo:sli_error:ratio_rate5m`, the server-side (5xx) error ratio that is the
  SLO's SLI. The canary **fails if it exceeds 0.01** (a 99% floor over the
  canary window).
- `job:http_request_duration_seconds:p99`, p99 request latency. The canary
  **fails if it exceeds 1s**.

Both use `failureCondition`, not `successCondition`, on purpose. The recording
rules yield `NaN` on an idle service (division by an empty selector), and a
`NaN` sample satisfies no threshold comparison. With `failureCondition`-only a
non-failing sample, `NaN` included, is scored Successful, so an idle canary
auto-promotes instead of stalling; `successCondition`-only would score the same
`NaN` as a failure and burn the budget on a service that simply has no traffic.
The tradeoff to make consciously: `failureCondition`-only means an idle canary
promotes hands-off. If you would rather an idle window block on a human, set
both conditions so the measurement is Inconclusive. `failureLimit: 1` rides out
a single scrape blip and aborts on a sustained breach.

On a breach ArgoCD sees the Rollout go Degraded and, with auto-rollback, the
canary is scaled to zero and the stable version keeps serving. That is the
"bad deploy recovers automatically" row of the resilience table, made concrete.

## Promotion direction: Kargo

Argo Rollouts gates a **single** environment's rollout on health. It does not
model promotion **between** environments (dev green, therefore promote this
exact artifact to prod). [Kargo](https://kargo.akuity.io/) is the newer project
that fills that gap: it watches for new artifacts, runs verification, and opens
promotions along a defined `dev -> prod` freight path, driving the same ArgoCD
Applications this layer already defines. It is the direction of travel for
multi-stage promotion; mentioned here as the next step, not wired up.

## Files

| File | What it is |
|------|------------|
| `appproject.yaml` | `AppProject nimbus`: source-repo allowlist, `nimbus` + `monitoring` destinations, least-privilege resource whitelists |
| `applicationset.yaml` | Git directory generator over `kubernetes/overlays/*`, one Application per env |
| `kustomization.yaml` | Collects the project + ApplicationSet (the bootstrap apply) |
| `rollouts/podinfo-rollout.yaml` | Opt-in Rollout that replaces the Deployment, canary strategy |
| `rollouts/analysistemplate-slo.yaml` | Prometheus AnalysisTemplate: error-ratio and p99 SLO gates |
| `rollouts/kustomization.yaml` | Builds the Rollout example on its own |
