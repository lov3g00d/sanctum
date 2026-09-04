# Chamber: local-agent-memory

An end-to-end test of [MemPalace](https://github.com/mempalace/mempalace) as a local,
no-API-key memory for an AI agent. A committed seed corpus (incidents, an ADR, a runbook) is
mined into a local palace; a fixed set of queries then proves the right memory comes back.
Everything runs on-machine: verbatim storage plus semantic search over a local embedding
model, no cloud and no API key.

This is the *memory* layer. It complements [`local-llm`](../local-llm/) (the model server,
which can also serve the embeddings) and [`local-sre-copilot`](../local-sre-copilot/) (which
does its own RAG over a fixed corpus). MemPalace is the reusable, MCP-native alternative:
memory you can wire into Claude Code itself.

## What it demonstrates

- A local agent-memory store stood up from nothing: `init` detects structure, `mine` ingests
  files, `search` recalls, with no LLM and no API key at write time.
- A deterministic recall test (`task test`): fixed corpus in, fixed queries, PASS/FAIL matrix
  out, in the same shape as `shared/redteam/run-validation.sh`. This is what makes an
  otherwise fuzzy "does memory work" question reproducible and CI-friendly.
- Two optional, opt-in layers: pointing the embedder at the local Ollama server, and wiring
  MemPalace's MCP server into Claude Code.

## Prerequisites

- The repo toolchain: `nix develop` from the repo root (provides `uv`, `jq`, and the
  `LD_LIBRARY_PATH` the embedding runtime needs).
- Disk for the embedding model (~30 MB for the default `all-MiniLM-L6-v2`, pulled on first
  `mine`).
- No GPU, no API key, no model server. The bundled MiniLM embedder runs on CPU with no
  external service; the `local-llm` Ollama server is not required.

## Stand up

```sh
cd chambers/local-agent-memory
task up            # uv sync (pins MemPalace) + build the palace from corpus/
task test          # the deterministic recall PASS/FAIL matrix
```

Then explore:

```sh
task search -- "why did the checkout endpoint get slow"
task status        # what has been filed, by wing/room
task wake-up       # the compact wake-up context MemPalace hands an agent
```

## Wiring into Claude Code (opt-in)

`task mcp` prints the `claude mcp add` command; it only prints, so editing your global Claude
Code config stays your call. Two things the printed line assumes:

- `mempalace-mcp` must be on PATH. Install it globally for that: `uv tool install mempalace`
  (the chamber's own `.venv` is enough for the tasks above, but Claude Code launches the MCP
  server outside this directory).
- Give it an absolute palace path so it resolves regardless of cwd, e.g.
  `claude mcp add mempalace -- mempalace-mcp --palace "$PWD/.palace"` from this directory.

Remove it later with `claude mcp remove mempalace`.

## A note on embeddings

The chamber ships the bundled `all-MiniLM-L6-v2` embedder: CPU-only, no external service, and
what `task test` is verified against. MemPalace can instead use a local Ollama embedding model
(reusing the `local-llm` chamber), but that path is configured in MemPalace's own config and is
not wired as a task here, because it was not verified on this box. Start with the default.

## Tear down

```sh
task down          # delete the generated palace and config; keeps corpus/ and .venv/
task clean         # also remove the uv venv
```

## An honest note on MemPalace

MemPalace fits a CPU-only box well (verbatim + embeddings, no LLM at write time, embedded
ChromaDB, first-party MCP, MIT). But treat its marketing skeptically: its headline "96.6%
recall" is an `all-MiniLM-L6-v2`-on-ChromaDB number that its own `BENCHMARKS.md` and an
independent critique (issue #703) attribute to good embeddings, not the palace architecture,
and its star-growth curve looks inflated. Being MIT and fully offline caps the downside (this
chamber is exactly how you decide for yourself). If the vendor's conduct bothers you, `txtai`
is a boring, honest, Apache-2.0 alternative with the same local + MCP story. See
[`local-agent-memory.md`](local-agent-memory.md).
