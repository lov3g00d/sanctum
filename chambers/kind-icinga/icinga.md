# Icinga, end to end

How the monitoring stack in this chamber actually works, from `helm install` to a
check going CRITICAL and firing a notification. Grounded in the `webapp` target,
the `check_http` service, and the notification defined under `icinga/`.

## The one idea

Icinga is an **active check scheduler with a notification engine**. It runs a
plugin against each thing you monitor on a fixed interval, turns the plugin's
exit code into a state (OK/WARNING/CRITICAL/UNKNOWN), tracks whether that state
is stable, and notifies the right people when it changes. It goes and asks; it
does not wait to be told.

That is the opposite of Prometheus, which scrapes numeric metrics and evaluates
alerting expressions over the resulting time series. Icinga thinks in **hosts and
services with discrete states**; Prometheus thinks in **labelled samples over
time**. This chamber is the check-and-notify counterpart to the pull-model setup
in `kind-slo-error-budget`.

## Two planes

**The engine** = **Icinga 2** (one StatefulSet). It holds the object config,
schedules checks, forks the check plugins, computes states, and runs
notifications. It exposes a REST API on 5665.

**The state and UI** = **Icinga DB** and **Icinga Web 2**. Icinga 2 does not talk
to the SQL database directly. It writes runtime state into **Redis**; the
**Icinga DB daemon** reads Redis and persists to **MariaDB**; **Icinga Web 2**
reads MariaDB (and Redis for live data) to draw the UI. This Redis-relay design
(Icinga DB) replaced the older direct-to-SQL IDO.

```
             checks              Redis            MariaDB
  plugins <--------- Icinga 2 ---------> Icinga DB ------> Icinga Web 2
             exit code          runtime  daemon   persist    (UI)
                                state
```

## A check, end to end

`task check-demo` walks this path for `webapp!http-health`:

1. Icinga 2's **checker** component fires the service's `check_command` on its
   `check_interval` (15s here). The command is `http`, which runs the
   `/usr/lib/nagios/plugins/check_http` plugin against `webapp.web.svc:8080/healthz`.
2. The plugin exits **0/1/2/3**. That exit code becomes the service state
   (OK/WARNING/CRITICAL/UNKNOWN). Its stdout becomes the check output, and
   anything after a `|` is performance data.
3. A bad result is **SOFT** at first. Icinga rechecks on `retry_interval` (5s)
   until `max_check_attempts` (2) is reached, then the state becomes **HARD**.
   This is what stops a single blip from paging anyone.
4. On the HARD transition, the **notification** component evaluates the
   `apply Notification` rule, checks the user's state/type filters and the
   `TimePeriod`, and runs the `NotificationCommand`. Here that appends a line to a
   log file inside the pod, which the demo prints.
5. When the app is healed, the next check is OK, the state goes back to HARD OK,
   and a **Recovery** notification fires the same way.

State is read back from the REST API (`/v1/objects/services`), not the UI, so the
whole OK to CRITICAL to OK arc is scriptable.

## The object model

Everything in Icinga is a typed object. The ones in `icinga/monitoring.conf`:

- **Host** `webapp` - the thing being monitored, with an `address` and its own
  check. A host groups services and is the top of the dependency tree.
- **Service** `http-health` - a specific check on a host. Carries the
  `check_command` and the scheduling knobs (`check_interval`, `retry_interval`,
  `max_check_attempts`).
- **CheckCommand** `http` - how to actually run a plugin: the executable plus how
  its arguments map to `vars.*` (here `vars.http_uri`, `vars.http_port`). Comes
  from the Icinga Template Library (ITL), which ships definitions for the standard
  Monitoring Plugins.
- **TimePeriod** `always` - when checks or notifications are active. Defined
  explicitly here because the chart disables `conf.d`, so the stock `24x7` period
  is not loaded.
- **User** `ops-oncall` - a notification recipient, with `states` and `types`
  filters (only notify me about these states and these event kinds).
- **NotificationCommand** `file-log` and an **apply Notification** rule - the
  command to run and the rule that attaches it to matching services
  (`assign where service.name == "http-health"`).

**`apply` rules** are the scaling mechanism: `apply Service "disk" to Host {...}`
generates that service on every host matching an `assign where` expression, so you
describe a thousand hosts' checks in a few rules instead of a thousand objects.

## The Nagios plugin API

Icinga's check plugins follow the Monitoring Plugins (formerly Nagios Plugins)
contract, which is why the ecosystem is huge and language-agnostic:

- **Exit code is the state**: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN.
- **Stdout is the human message**; the part after a `|` is machine-readable
  **performance data** (`label=value;warn;crit;min;max`) that feeds graphing.
- Anything that respects this contract is a valid check, from `check_http` to a
  ten-line shell script. Writing one is a core SRE task.

## Config delivery: why the REST API

The chart mounts Icinga 2's entire `/etc/icinga2` from a ConfigMap and sets
`disable_confd: true`, so you cannot drop `.conf` files into `conf.d`. There are
three real ways to manage Icinga 2 config, and this chamber uses the middle one:

- **Files in `conf.d`** - fine for a single static node, awkward in a container.
- **The REST API config-package endpoint** - `POST /v1/config/packages/<pkg>`
  then `POST /v1/config/stages/<pkg>` with a map of files. Icinga validates the
  stage, and on success reloads. This is version-controllable and GitOps-friendly,
  and it is what `scripts/apply-config.sh` does.
- **Icinga Director** - a web module and its own database that manages config with
  import/sync from external sources, deployed to Icinga 2 over the API. The right
  tool at fleet scale; enabled here so the module is available in the UI, though
  this chamber authors config through the API path above rather than the Director.

A subtlety worth knowing: in Icinga config strings, `$` delimits macros, so a
shell `$(date)` inside a command throws a macro error. Use Icinga's own macros
(`$icinga.long_date_time$`, `$service.output$`) or escape a literal `$` as `$$`.

## Notifications

Notifications are objects too, and they only fire when several conditions line
up, which is exactly the anti-noise design:

- the state change is to a **HARD** state (or a re-notification interval elapses),
- the event **type** (Problem, Recovery, Acknowledgement, ...) is in the
  notification's and the user's `types` filter,
- the **state** is in their `states` filter,
- the current time is inside the **TimePeriod**,
- notifications are enabled on the host, the service, the user, and globally.

Miss one and nothing sends, which is the usual reason a "broken" notification is
actually a filter or a missing TimePeriod.

## Distributed Icinga (beyond this chamber)

Real deployments run Icinga 2 in **zones**: a master (or an HA master pair),
optional **satellites** per site or network segment, and **agents** on monitored
hosts. Config syncs down the zone tree and check execution is delegated outward,
so checks run close to the target and survive a link outage. This chamber is a
single master zone, which is all the check-and-notify model needs to be clear.

## Icinga for Kubernetes (the other product)

Separate from the classic stack, **Icinga for Kubernetes** is a collector daemon
that watches the Kubernetes API and syncs resource state (pods, deployments,
nodes) into a database for the Icinga Kubernetes Web module. It complements the
check engine rather than replacing it, and mostly surfaces object state you could
also see with `kubectl`, plus optional Prometheus metric sync. It is enabled in
this chamber (with its image tag pinned to a published version, since the chart's
default tag was never released) and appears as the Kubernetes module in Icinga
Web 2, but the center of gravity stays on the classic paradigm.

## The install this chamber runs

`task install` deploys the full `icinga-stack` chart: Icinga 2, the Icinga DB
daemon, Icinga Web 2 (with the Director and Kubernetes modules), the
Icinga-for-Kubernetes collector, Redis, and one MariaDB per database (Icinga DB,
Icinga Web 2, Director, and Kubernetes). Component images stay on the chart's
tested pinned versions, with only the collector tag corrected to a published
release. `task deploy` adds the sample app and a NodePort for the UI, and
`task apply` pushes `icinga/monitoring.conf` through the REST API.

## The one-paragraph version

Icinga 2 is an active monitoring engine: it runs Monitoring-Plugins check
commands on a schedule, turns each plugin's exit code into a host or service
state, holds a failing state as SOFT until `max_check_attempts` makes it HARD,
and fires notifications on the HARD transition through users, time periods, and
state/type filters. State flows Icinga 2 to Redis to the Icinga DB daemon to
MariaDB to Icinga Web 2. Config is declarative typed objects (Host, Service,
CheckCommand, TimePeriod, User, Notification) scaled with `apply` rules, delivered
here through the REST API config-package endpoint because the chart disables
`conf.d`. It is the discrete-state, push-model, notify-on-change counterpart to
Prometheus's numeric pull-and-alert model.
