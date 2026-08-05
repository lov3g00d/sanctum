# Red team and purple-team validation

`docs/security-architecture.md` makes a claim: these controls stop these
attacks. This document is the offensive test that backs the claim. It maps
MITRE ATT&CK for Containers techniques to the attack attempts under
`shared/redteam/attacks/`, names the Sanctum control that stops each one, and states how
the stop is verified. Where `security-architecture.md` reasons about the defence,
this exercises it.

Everything here is authorized self-validation of the operator's own platform and
own sandbox account. The tooling is on-demand and lives outside the always-on
platform module on purpose (see `shared/redteam/README.md`).

## ATT&CK for Containers matrix

| Tactic | Technique | Attempt (manifest) | Control that stops it | How it is verified |
|--------|-----------|--------------------|-----------------------|--------------------|
| Privilege Escalation | T1610 Deploy Container | `01-privileged-pod.yaml` | PSA restricted + Kyverno `require-drop-all-capabilities` | `kubectl apply` is rejected at admission with a policy denial |
| Privilege Escalation | T1611 Escape to Host | `01-privileged-pod.yaml`, `02-hostpath-mount.yaml`, `04-host-namespace.yaml` | PSA restricted (privileged, hostPath, hostPID/hostNetwork all forbidden) | Admission rejects each apply |
| Execution | T1610 Deploy Container | `03-run-as-root.yaml` | PSA restricted + Kyverno `require-run-as-non-root` / `require-readonly-rootfs` / `require-resource-limits` | Admission rejects the apply |
| Initial Access | T1610 Deploy Container (supply chain) | `05-unsigned-image.yaml` | Kyverno `verify-image-signatures` (Enforce) | Admission rejects the unsigned sanctum-ECR image; a policy-clean pod template isolates the signature check as the sole reason |
| Credential Access | T1552.001 Credentials In Files | `06-shadow-read.yaml` | Tetragon `sanctum-block-credential-access` (SIGKILL) + Falco sensitive-file read | Pod is admitted, then the `/etc/shadow` read is SIGKILLed (exit 137) and the container CrashLoops |
| Credential Access | T1528 Steal Application Access Token | `07-satoken-exfil.yaml` | default-deny egress NetworkPolicy (prevent) + Falco token-read (detect) | Pod is admitted; the exfil curl to an external host times out, the probe reports `BLOCKED-AS-EXPECTED` |
| Lateral Movement | T1021 Remote Services | `08-lateral-movement.yaml` | default-deny egress NetworkPolicy (sanctum) | Pod is admitted; the cross-namespace / control-plane connect is dropped |
| Execution / C2 | T1059 Command and Scripting Interpreter | `09-reverse-shell.yaml` | Falco shell-spawn (detect) + default-deny egress NetworkPolicy (prevent) | Pod is admitted; the shell is flagged by Falco and the C2 callback is dropped |

`run-validation.sh` reads the `redteam.sanctum/control-class` label off each
manifest to decide which check to run: `admission-deny` expects the apply to be
rejected, `runtime-kill` expects the admitted pod to be killed (exit 137),
`network-block` expects the admitted pod to report its egress was dropped.

### Two mappings that differ from the naive reading

- **T1610 supply chain (05).** Kyverno `verify-image-signatures` only matches
  `*.dkr.ecr.eu-central-1.amazonaws.com/sanctum/*`. A generic public image is out
  of scope for that policy by design, and is instead rejected by
  `disallow-latest-tag` plus PSA restricted and the pod-hardening policies. The
  attempt therefore references the sanctum ECR repo with an unsigned tag so the
  signature verification is the control under test.
- **T1528 SA-token (07).** The Tetragon TracingPolicy SIGKILLs on writes to
  `/etc/shadow`, `/etc/sudoers`, `/root/.ssh` and reads of `/etc/shadow` and the
  kubelet PKI. It does not cover the projected SA-token path. So the token read
  is caught by Falco (alert) and the exfil by the default-deny egress
  NetworkPolicy (block), not by an inline kill. The manifest is mapped
  accordingly.

## Methodology: the kill chain mapped to the defence

The attempts trace a compromise from the outside in. Each phase names what an
attacker tries and the earliest Sanctum layer that ends the attempt.

| Phase | Attacker goal | Sanctum response | Where |
|-------|---------------|-----------------|-------|
| Recon | Map the cluster from a foothold | Least-privilege RBAC and default-deny NetworkPolicy limit what a pod can see and reach | `tools/kube-hunter-job.yaml`, `networkpolicy.yaml` |
| Initial Access | Land a tampered or unsigned image | cosign keyless signing in CI, verified at admission (Enforce) | `05-unsigned-image.yaml` vs `verify-images.yaml` |
| Execution | Get privileged code running in a pod | PSA restricted + Kyverno reject privileged, root, host-mount, host-namespace pods at admission | `01`-`04` |
| Persistence | Tamper with system paths to survive | Read-only rootfs, and Tetragon SIGKILLs writes to credential files; Falco alerts on sensitive-dir writes | `06-shadow-read.yaml`, `falco-rules.yaml`, `tetragon.tf` |
| Privilege Escalation | Escape the container, or escalate IAM | No privileged/host access survives admission; IAM enumerated read-only for privesc paths | `01`/`02`/`04`, `tools/pacu.md` |
| Credential Access | Read `/etc/shadow` or steal the SA token | Tetragon kills the shadow read; Falco alerts on token read by a shell | `06`, `07`, `falco-rules.yaml` |
| Lateral Movement | Pivot to another namespace or service | default-deny egress: a pod talks only to DNS and its declared dependencies | `08-lateral-movement.yaml` |
| Exfiltration / C2 | Beacon out or exfil data | default-deny egress drops off-cluster connections; Falco flags off-cluster egress and shell spawn | `07`, `09`, `networkpolicy.yaml` |

The through-line is defence in depth with the emphasis shifted left. Most
attempts die at admission (PSA and Kyverno), the cheapest place to stop them.
What admission cannot judge (behaviour of a legitimately-scheduled pod) is
caught at runtime by Tetragon (kill) and Falco (alert), and contained by the
network layer (default-deny egress). Nothing depends on a single control:
a privileged pod is refused by both PSA and Kyverno, and an exfil attempt is both
blocked by NetworkPolicy and alerted on by Falco.

## What this validates about the DevSecOps controls

| Control | Validated by | Evidence of a working control |
|---------|-------------|-------------------------------|
| PSA restricted | 01, 02, 03, 04 | Privileged, host-mount, root, and host-namespace pods are refused at admission |
| Kyverno pod hardening | 01, 03 | run-as-non-root, readonly-rootfs, drop-all-caps, resource-limits reject the same attempts, in depth behind PSA |
| cosign verifyImages | 05 | An unsigned sanctum-ECR image is refused at admission |
| Tetragon (enforce) | 06 | The `/etc/shadow` read is SIGKILLed in-kernel before it completes |
| Falco (detect) | 06, 07, 09 | Shell spawn, token read, and sensitive-file access raise alerts |
| NetworkPolicy default-deny | 07, 08, 09 | Token exfil, cross-namespace pivot, and C2 callback are all dropped |
| Pod Identity least-privilege | `tools/pacu.md` | IAM enumeration finds no privilege-escalation path for the audited principal |
| CSPM posture | `tools/scoutsuite.md`, CI Prowler | Account-level drift surfaces in a read-only sweep, matching the weekly Prowler CronJob |

A green matrix is the deliverable: it shows the controls named in
`security-architecture.md` are not just present but actually blocking. A red row
is more valuable still. It means a control drifted (a policy flipped to Audit, a
NetworkPolicy loosened, a namespace un-labelled), and it points straight at the
manifest to fix. That is the purple-team loop: attack your own controls on a
cadence, and turn every gap back into a tightened control before an adversary
finds it first.
