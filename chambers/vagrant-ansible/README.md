# Chamber: vagrant-ansible

A 4-VM three-tier web application on libvirt, provisioned end to end by a
deliberately complex Ansible project. HAProxy load-balances two Flask web
servers that read from a PostgreSQL database over an isolated private network.
Ansible's home turf: real hosts over SSH, roles, templates, handlers, Vault,
and a zero-downtime rolling deploy.

## Topology

```
        host ── curl :80 ──▶  lb (HAProxy)
                                 │  round-robin, /healthz checks
                        ┌────────┴────────┐
                     web1 (Flask)      web2 (Flask)
                        └────────┬────────┘
                                 ▼
                             db (PostgreSQL)
```

Four `generic/debian12` VMs on an isolated libvirt network (`192.168.56.0/24`,
forward mode none). Each guest also has Vagrant's management NAT for SSH and
package installs. The host holds `.1` on the private bridge, so it can curl the
load balancer directly.

## What the Ansible demonstrates

- **Grouped inventory** with a nested child group (`webstack`), plus
  `group_vars`, `host_vars`, and per-host `private_ip`.
- **Four roles** (`common`, `postgresql`, `webapp`, `haproxy`), each with tasks,
  handlers, templates, and defaults.
- **Ansible Vault**: the DB password is encrypted and referenced through the
  `vault_` indirection pattern; the app connects with a least-privilege DB user,
  so the secret is genuinely load-bearing.
- **Jinja2 with a custom filter plugin**: HAProxy `server` lines are generated
  from the `webservers` group by a `haproxy_backends` filter in `filter_plugins/`.
- **Handlers and `flush_handlers`**: config changes notify restarts/reloads;
  PostgreSQL is restarted mid-role before the app roles depend on it.
- **Collections** via `requirements.yml` (`community.postgresql`,
  `community.general`, `ansible.posix`).
- **Tags** (`common`, `db`, `web`, `lb`) to run tiers independently.
- **Zero-downtime rolling deploy** (`deploy.yml`): `serial: 1` plus HAProxy
  drain via the admin stats socket, `delegate_to` the load balancer, disable →
  redeploy → health-check → re-enable, one node at a time.
- **Idempotence**: a second `task provision` should report no changes.

## Prerequisites

`nix develop` from the repo root provides `vagrant` (unfree, BSL - scoped in the
flake) with the bundled `vagrant-libvirt` plugin, plus `ansible` and `task`.
**libvirtd is a host prerequisite** (`virtualisation.libvirtd.enable = true`,
your user in the `libvirtd` group) - a `nixos-rebuild switch` you own, not
something the flake can provide.

## Use

```sh
cd chambers/vagrant-ansible
task up            # vagrant up + ssh-config + collections + full provision + demo
task ping          # ansible connectivity check
task provision     # re-run the playbook (idempotence: second run = no changes)
task demo          # curl the LB, watch round-robin across web1/web2 + the DB value
task deploy        # rolling deploy (VERSION=3.0 task deploy to bump the version)
task rolling-demo  # curl the LB continuously during a rolling deploy, count non-200s
task vault-edit    # edit the encrypted vault
task down          # destroy the VMs
```

The load balancer is at `http://192.168.56.10/`; its stats page is on `:8404`
(admin/statsadmin). The `.vault_pass` committed here is a lab-only password that
protects nothing real - it exists so a fresh `task up` can decrypt.

## Reference

[`ansible.md`](ansible.md) is a deep-dive on how the project is structured and
why (inventory and variable precedence, roles and handlers, Vault, the custom
filter, and the rolling-deploy mechanics), grounded in this chamber.
[`ansible-architecture.html`](ansible-architecture.html) is a self-contained
visual reference to the topology and the Ansible concepts (open it in a browser).
