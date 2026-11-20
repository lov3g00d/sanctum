# Chamber: local-langfuse

A self-hosted [Langfuse](https://langfuse.com) stack on your own machine: LLM observability
with no cloud account and no per-trace bill. `task up` brings up the full stack (web, worker,
Postgres, ClickHouse, Redis, MinIO), seeds a project and API keys, and prints the UI URL.
`task trace` sends one instrumented call to the [`local-llm`](../local-llm/) model and lands it
in Langfuse as a trace.

This chamber is the *observability* over the [`local-llm`](../local-llm/) *substrate*: that
chamber serves a model behind an OpenAI-compatible API, this one watches the calls.

## What it demonstrates

- A real Langfuse deployment (the same six services the official docker-compose runs), seeded
  headless so there is no first-run signup: the project and keys exist the moment it is healthy.
- The `langfuse.openai` drop-in wrapper tracing an OpenAI-compatible call to a local model,
  so the trace in the UI is a genuine local-LLM request, not a canned demo.
- A deterministic PASS/FAIL that a trace round-trips the whole pipeline: SDK → Redis → worker →
  ClickHouse → public API.

## Prerequisites

- The repo toolchain: `nix develop` from the repo root (provides `docker` client, `uv`, `jq`,
  `curl`).
- A running Docker daemon. This is a host prerequisite, the way libvirtd is for the `vagrant-*`
  chambers; the flake ships the client, not the daemon.
- For `task trace`: the [`local-llm`](../local-llm/) server running (`cd ../local-llm && task up`).
- Room to run it. Six containers, with ClickHouse the memory-hungry one, alongside a resident
  12B model on the same laptop is a real squeeze. First start pulls a few GB of images; after
  that `task up` is ~25s.

## Stand up

```sh
cd chambers/local-langfuse
task up             # start the stack, seed a project + keys, wait until healthy
```

It prints the UI URL (http://localhost:3000), the seeded login, and the project keys. Open the
UI and log in, or drive it from the tasks below.

## Explore

```sh
task trace          # trace one call to the local-llm model (needs ../local-llm up)
task test           # deterministic PASS/FAIL: a trace round-trips the stack
task status         # container health + UI URL
task logs SERVICE=langfuse-worker   # tail one service
```

`task trace MODEL=<tag>` overrides the model; with no override it picks the first local
(non-`-cloud`) model Ollama has pulled. The task prints the direct trace URL; open it to see the
generation, its inputs and outputs, latency, and token usage.

## A note on Langfuse v4

v4 defaults to `events_only` write mode, so the **legacy** read endpoints (`GET
/api/public/traces`) return 404 by design. The current read path is the v2 API
(`GET /api/public/v2/observations`), which is what `task test` polls. Traces render in full in
the UI; the v2 read API is still filling in field coverage in this release, so treat it as an
existence check, not a full export.

## Tear down

```sh
task down           # stop the stack, keep volumes and .env (task up restores state in seconds)
task down -- --clean  # also drop the volumes and generated .env for a from-scratch reset
```

Secrets are generated once into `.env` (gitignored) and reused on every run. `ENCRYPTION_KEY`
protects rows already written to the database, so the two are wiped together or not at all:
`down` keeps both, `down --clean` removes both. Deleting `.env` while the volumes survive is the
one way to desync them into cryptic auth errors.
