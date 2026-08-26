# Ansible on Windows, end to end

How managing a Windows Server with Ansible differs from Linux, grounded in this
chamber's IIS + PowerShell provision over WinRM.

## The one idea

Ansible manages Windows the same way it manages Linux (agentless, push, modules
that converge state), but over a **different transport** and with a **different
module family**. The transport is **WinRM** (or SSH on newer Windows), not SSH by
default; the modules are the `win_*` family shipped in the `ansible.windows` and
`community.windows` collections. Everything else (inventory, roles, variables,
handlers, idempotence) is identical.

## WinRM: the transport

**WinRM** (Windows Remote Management) is Windows' built-in remote-execution
service, an implementation of WS-Management over HTTP(S). Ansible talks to it
instead of SSH:

- The controller needs the **`pywinrm`** Python library (in this chamber it is
  added to Ansible's Python through the flake). Without it the connection plugin
  cannot load.
- Ports: **5985** (HTTP) and **5986** (HTTPS). The lab uses 5985.
- Connection variables (in `group_vars/windows.yml`):
  ```yaml
  ansible_connection: winrm
  ansible_user: vagrant
  ansible_password: vagrant
  ansible_port: 5985
  ansible_winrm_transport: basic
  ansible_winrm_server_cert_validation: ignore
  ```

### Authentication transports (the part that bites)

`ansible_winrm_transport` picks how credentials are exchanged, and each has
tradeoffs:

- **basic** - simplest; only local accounts; over HTTP it requires the listener
  to allow unencrypted basic auth (Vagrant boxes enable this for the lab user).
- **ntlm** - local or domain accounts, encrypts the payload over HTTP; needs
  `requests_ntlm` on the controller. A common production default without a domain.
- **kerberos** - domain (Active Directory) auth; needs Kerberos libraries and a
  realm. The enterprise default in an AD environment.
- **credssp** - allows credential delegation (the "second hop"); needs extra libs.

The gusztavvargadr box exposes WinRM ready to use, so the lab connects with
`basic` over 5985. In production you would use NTLM or Kerberos over 5986 (HTTPS).

### WinRM vs SSH on Windows

Windows Server 2019+ ships **OpenSSH server**, so Ansible can also use
`ansible_connection: ssh` against Windows. SSH sidesteps the WinRM transport/auth
maze and is simpler for key-based auth, but WinRM is still the classic path and
what most existing playbooks and the `win_*` modules assume. Know both.

## The `win_*` module family

Windows has its own modules because the OS primitives differ. The ones here:

- **`ansible.windows.win_feature`** - install/remove Windows roles and features
  (`Web-Server` for IIS, `AD-Domain-Services` for a domain controller).
- **`ansible.windows.win_service`** - manage Windows services (`W3SVC` is IIS).
- **`ansible.windows.win_template` / `win_copy`** - render/copy files, same idea
  as the Linux versions but Windows paths.
- **`ansible.windows.win_user`** - local users and group membership.
- **`ansible.windows.win_reboot`** - reboot and wait for the host to return
  (feature installs often need it; `reboot_required` in the result tells you).
- **`ansible.windows.win_powershell`** - run a PowerShell script and report
  results; set `$Ansible.Changed`/`$Ansible.Failed` from inside the script to
  drive idempotence and status.
- **`community.windows.win_firewall_rule`** - manage Windows Firewall rules
  (opening port 80 so the page is reachable).
- **`community.windows.win_timezone`** - set the timezone.

## PowerShell through Ansible

`win_powershell` is the escape hatch for anything without a dedicated module. The
script runs on the target; you communicate back through the `$Ansible` object:

```powershell
$marker = "C:\sanctum\provisioned.txt"
if (Test-Path $marker) { $Ansible.Changed = $false }
else { ...; $Ansible.Changed = $true }
```

That `Test-Path` guard is how you make an arbitrary PowerShell task **idempotent**
- the same discipline as `creates:` on a Linux `command`. Without it, a raw script
reports changed every run.

## Idempotence still holds

The `win_*` state modules are idempotent like their Linux counterparts: a second
`task provision` reports no changes. The only task that needs care is
`win_powershell`, handled with the marker-file guard above. This is the same
promise as the Linux chamber, on a different OS.

## How it maps to the Linux chamber

| Concern | Linux (`vagrant-ansible`) | Windows (`vagrant-windows`) |
|---|---|---|
| Transport | SSH | WinRM (5985) |
| Controller dep | ssh client | `pywinrm` |
| Package/role install | `apt`, `win_feature` n/a | `win_feature` |
| Service | `systemd` module | `win_service` |
| Ad-hoc code | `shell`/`command` | `win_powershell` |
| Escalation | `become` (sudo) | admin token via WinRM (no become) |

## The one-paragraph version

Ansible manages Windows with the same agentless, push, idempotent model as Linux,
but connects over WinRM (needing `pywinrm` on the controller) instead of SSH, and
uses the `win_*` module family from the `ansible.windows`/`community.windows`
collections. This chamber connects over WinRM with basic auth, installs the IIS
role with `win_feature`, serves a templated page, creates a local user, opens the
firewall, and runs an idempotent PowerShell step, all re-runnable to the same
state. Swap the transport to NTLM or Kerberos over HTTPS and it is the production
pattern.
