# shared

Reusable building blocks that Kubernetes chambers draw on, so labs reference them instead of
copying:

- `charts/` - workload Helm charts. `podinfo` is the standard cloud-native test app used to
  exercise a platform end to end (probes, HPA, scraping, SLOs, canary rollouts, admission policies).
- `gitops/` - the ArgoCD `AppProject` and `ApplicationSet` that deliver the workload chart per environment.
- `docker/` - the multistage Dockerfile that builds the workload image from pinned upstream
  source, and a hardened Nginx reverse proxy.
- `redteam/` - MITRE-mapped attack fixtures and a validation harness for checking that a
  cluster's security controls actually block them.

A chamber consumes these by pointing at them: ArgoCD syncs `shared/charts/podinfo`, CI builds
`shared/docker/podinfo.Dockerfile`, and the security workflow applies `shared/redteam`.
