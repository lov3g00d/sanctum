# Runbook: Pod in CrashLoopBackOff

## Symptom
A Kubernetes pod repeatedly restarts; `kubectl get pods` shows
`CrashLoopBackOff` with a rising restart count.

## Severity
SEV3 unless it takes a user-facing service below its replica floor, then SEV2.

## Diagnose
1. Identify the pod and container:
   `kubectl -n <ns> get pods` then `kubectl -n <ns> describe pod <pod>`.
2. Read the last logs, including the previous crashed container:
   `kubectl -n <ns> logs <pod> --previous`.
3. Check the exit code and reason in `describe` (OOMKilled, Error, exit code).

## Common causes and fixes
- **OOMKilled**: the container exceeded its memory limit. Raise
  `resources.limits.memory` (and requests), or fix the leak. A controller or
  broker that OOMs under churn needs a higher limit, not more restarts.
- **Bad config / missing secret**: the app exits on startup because a required
  env var, config file, or mounted secret is absent. Fix the ConfigMap/Secret
  and the mount.
- **Failing readiness/liveness probe**: an aggressive probe kills a slow-starting
  app. Loosen `initialDelaySeconds` / `failureThreshold`.
- **Dependency not reachable at boot**: the app crashes because it cannot reach
  the database or a peer. Fix networking/DNS or add a retry/backoff at startup.
- **Image or command error**: wrong entrypoint, missing binary, or a failed
  migration. Check the command and the image tag.

## Mitigate
- If a recent change caused it, roll back the deployment.
- If it is resource-related, raise limits and let it stabilize.

## Verify recovery
The pod reaches `Running` and `Ready`, restart count stops climbing.
