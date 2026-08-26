# Chamber: vagrant-windows

A Windows Server VM on libvirt, configured entirely by Ansible over **WinRM**.
Installs the IIS web role with a templated page, creates a local user, installs
PowerShell 7 and VS Code via Chocolatey, and runs an idempotent PowerShell step.
The Windows counterpart to the Linux `vagrant-ansible` chamber: same tooling,
different platform and transport.

## Stack

One `gusztavvargadr/windows-server` VM (Windows Server, WinRM pre-enabled) on an
isolated libvirt network. Ansible manages it with the `ansible.windows` and
`community.windows` collections (the `win_*` modules), connecting over **WinRM**
(port 5985), not SSH. The host holds `.1` on the private bridge, so it can curl
the IIS page directly.

## Prerequisites

`nix develop` from the repo root provides `vagrant`, `ansible` (with `pywinrm`,
required for the WinRM connection), and `task`. **libvirtd is a host
prerequisite** (your user in the `libvirtd` group). Because Windows Server boots
via **UEFI**, libvirtd also needs OVMF firmware
(`virtualisation.libvirtd.qemu.ovmf.enable = true` on NixOS); the Taskfile points
`VAGRANT_LIBVIRT_OVMF_CODE` at the resulting `/run/libvirt/nix-ovmf/` path. The
first `vagrant up` pulls a multi-gigabyte Windows box and boots Windows, so it is
slow.

## Use

```sh
cd chambers/vagrant-windows
task up            # boot the VM + install collections + provision + demo
task ping          # WinRM connectivity check (win_ping)
task provision     # re-run the playbook (idempotent)
task psinfo        # run a PowerShell command over WinRM (OS name/version)
task demo          # curl the IIS page the VM serves
task down          # destroy the VM
```

The IIS page is at `http://192.168.57.10/`. Lab credentials are the well-known
Vagrant `vagrant` / `vagrant` (used for WinRM); the created app user is
`appadmin`.

## What the provision configures

Three roles, applied over WinRM:

- **common**: sets the timezone, creates the local `appadmin` user, and runs an
  idempotent PowerShell step (writes a marker file).
- **iis**: installs the IIS `Web-Server` role, ensures `W3SVC` is running,
  deploys a templated `index.html`, and opens firewall port 80.
- **tools**: installs PowerShell 7 (`pwsh`) and VS Code via Chocolatey, plus the
  VS Code PowerShell extension.

## What it demonstrates

- **Ansible manages Windows over WinRM**: `ansible_connection: winrm` with
  `pywinrm` on the controller, no SSH. The whole point that trips people up.
- **The `win_*` modules**: `win_feature` (install IIS), `win_service`,
  `win_template`, `win_user`, `win_firewall_rule`, `win_reboot`, `win_powershell`.
- **Chocolatey package installs**: `win_chocolatey` installs PowerShell 7
  (`pwsh`) and VS Code, so the box comes with a working admin toolset.
- **PowerShell through Ansible**: `win_powershell` runs a script and reports
  changed via `$Ansible.Changed`, kept idempotent with a marker file.
- **Idempotence on Windows**: a second `task provision` reports no changes.

## Reference

[`ansible-windows.md`](ansible-windows.md) is a deep-dive on managing Windows
with Ansible (WinRM vs SSH, authentication transports, `pywinrm`, the `win_*`
module family, and how this differs from managing Linux), grounded in this
chamber.
