# GitOps and progressive delivery

The scenario's "bad deploy recovers automatically" row is not free; something has
to deliver the app, notice a regression, and undo it without a human. In Nimbus
that something is ArgoCD, and the delivery custom resources it reconciles live in
[`gitops/`](../gitops/).

Two ownership layers, kept apart on purpose:

- **The platform installs ArgoCD** (Terraform `helm_release`, namespace
  `argocd`). ArgoCD is treated as infrastructure, created and upgraded like the
  cluster itself.
- **The GitOps layer tells ArgoCD what to deliver.** An `AppProject` scopes what
  may be synced, and an `ApplicationSet` with a git directory generator turns
  each Kustomize overlay under `kubernetes/overlays/*` into its own Application.
  Adding an environment is adding a directory, not authoring another Application.

This is the modern shape: `ApplicationSet` instead of a folder of hand-written
`Application` objects (app-of-apps), and `Argo Rollouts` for a canary that is
gated on the service's own SLO. The canary's `AnalysisTemplate` queries the same
Prometheus recording rules the dashboards and burn-rate alerts use
(`slo:sli_error:ratio_rate5m`, `job:http_request_duration_seconds:p99`) and
aborts the rollout if the error ratio crosses 0.01 or p99 crosses 1s, so a
regression rolls back before it burns the error budget.

The mechanics, including why ApplicationSets beat app-of-apps, how the SLO gate
handles an idle service, and where Kargo fits for cross-environment promotion,
are in [`gitops/README.md`](../gitops/README.md).
