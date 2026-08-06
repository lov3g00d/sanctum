# redteam

Purple-team validation for the Nimbus platform. Every artifact here is an attack
**attempt** paired with the Nimbus control that is supposed to stop it, wired so
you can prove each control actually fires. This is offensive tooling used for a
defensive end: it does not add protection, it verifies the protection already
built in `terraform/modules/platform/` works.

If `docs/security-architecture.md` is the claim ("these controls stop these
attacks"), this directory is the test that backs the claim.

## Authorization and scope

This is authorized self-validation of the operator's **own** reference platform
and **own** sandbox AWS account (`123456789012`). Nothing here targets a
third party. The Kubernetes attempts run against a cluster you own; the AWS
runbooks (`tools/pacu.md`, `tools/scoutsuite.md`) run read-only against your own
account with the `SecurityAudit` credentials. Do not point any of this at
infrastructure you do not own and operate.

## On-demand, not platform config

This lives at the repo top level, deliberately outside
`terraform/modules/platform/`, `charts/`, and `gitops/`. It is run by hand when
you want to validate the controls, not reconciled onto the cluster continuously.
Applying an attack manifest schedules a workload that a control is meant to
reject or kill; that belongs in a manual validation run, never in always-on
GitOps.

## Layout

| Path | What it is |
|------|-----------|
| `attacks/` | One manifest per attack attempt, labelled with its MITRE technique, the control that should stop it, and the expected outcome. |
| `run-validation.sh` | Applies each attempt, checks the matching control blocked it, prints a PASS/FAIL matrix, cleans up. |
| `tools/kube-hunter-job.yaml` | In-cluster recon (kube-hunter `--pod`) in a throwaway `redteam` namespace. |
| `tools/pacu.md` | Runbook: AWS IAM privilege-escalation enumeration, read-only. |
| `tools/scoutsuite.md` | Runbook: AWS CSPM enumeration, read-only. |
| `../docs/red-team.md` | The MITRE ATT&CK for Containers matrix and methodology. |

## Attack attempts and the control each one validates

| # | Attempt | Class | Control that stops it |
|---|---------|-------|-----------------------|
| 01 | privileged pod | admission-deny | PSA restricted + Kyverno pod-security |
| 02 | hostPath `/` mount | admission-deny | PSA restricted (hostPath forbidden) |
| 03 | run as root, no hardening | admission-deny | PSA restricted + Kyverno run-as-non-root |
| 04 | hostPID / hostNetwork | admission-deny | PSA restricted (host namespaces forbidden) |
| 05 | unsigned nimbus-ECR image | admission-deny | Kyverno verify-image-signatures (Enforce) |
| 06 | read `/etc/shadow` | runtime-kill | Tetragon SIGKILL + Falco |
| 07 | SA-token exfil | network-block | default-deny egress NetworkPolicy + Falco |
| 08 | cross-namespace pivot | network-block | default-deny egress NetworkPolicy |
| 09 | reverse shell | network-block | default-deny egress NetworkPolicy + Falco |

Attempts 01-05 are built to fail admission: the rejection is the pass. Attempts
06-09 are otherwise policy-clean (non-root, read-only rootfs, all caps dropped,
seccomp RuntimeDefault, resource limits, pinned tags) so they pass admission on
purpose. The point is that the runtime or network layer, not admission, catches
them.

Two mappings are worth calling out because they differ from a naive reading:

- **05** verifies image signatures, and Kyverno `verify-image-signatures` is
  scoped to `*.dkr.ecr.eu-central-1.amazonaws.com/nimbus/*`. A generic public
  image is out of scope for that policy by design and is instead rejected by
  `disallow-latest-tag` plus PSA and the pod-hardening policies. So the manifest
  references the nimbus ECR repo with an unsigned tag to isolate the signature
  check.
- **07** exfiltrates a service-account token. The Tetragon kill policy covers
  `/etc/shadow` and the kubelet PKI, not the projected SA-token path, so the
  token read is caught by Falco (detect) and the exfil by the default-deny
  egress NetworkPolicy (prevent), not by an inline kill.

## Running the validation suite

Preview what would run, applying nothing:

```
./run-validation.sh --explain
```

Run it against a cluster you own:

```
./run-validation.sh --context my-nimbus-cluster
```

It applies each attempt into the `nimbus` namespace, checks the matching control
stopped it, prints the PASS/FAIL matrix, and deletes everything it created. It
exits non-zero if any attempt did not resolve to PASS, so it can double as a
manual assurance gate. It needs `kubectl` and `yq` on PATH.

## Running the tools

kube-hunter, in a throwaway namespace:

```
kubectl apply -f tools/kube-hunter-job.yaml
kubectl -n redteam wait --for=condition=complete job/kube-hunter --timeout=300s
kubectl -n redteam logs job/kube-hunter
kubectl delete namespace redteam
```

Pacu and ScoutSuite are interactive AWS enumeration; follow `tools/pacu.md` and
`tools/scoutsuite.md`. Both run read-only against the sandbox account only.

## CI

`cicd/.github/workflows/redteam.yml` runs a report-only version of this on
`workflow_dispatch` and weekly: kube-hunter, a Nuclei DAST pass against the dev
endpoint, and a read-only Prowler sweep. It never blocks a merge or a deploy; it
is scheduled assurance, and its findings are uploaded as artifacts for triage.
