# Local agent memory with MemPalace

An LLM forgets everything between sessions. Agent memory is the layer that fixes that: a store
the agent writes to and later searches, so "we already switched to GraphQL and here is why"
survives past the context window. This chamber stands one up locally and proves it recalls,
with no cloud and no API key.

## The model: verbatim storage plus semantic search

MemPalace does not summarize with an LLM at write time. It stores source text **verbatim** in
"drawers", organized into "rooms" (topics) inside "wings" (projects), and answers a query by
embedding it and doing nearest-neighbour search over the drawers. The write path is just
chunk-and-embed. That is precisely why it runs well on a GPU-less box: the expensive part of
most memory systems is an LLM call on every write to build a knowledge graph, and MemPalace
skips it.

The flow is three verbs:

- `init <dir>` - detect structure and write the palace config. Heuristics-only with `--no-llm`,
  so it needs no model at all.
- `mine <dir>` - ingest the files into the palace (chunk, embed, store). First run pulls the
  ~30 MB `all-MiniLM-L6-v2` embedding model.
- `search "query"` - recall. Optionally scoped `--wing`/`--room`.

## Why this chamber is corpus-driven

A memory system's honest test is "put known things in, ask for them back, check you get the
right ones." That is only reproducible if the input is fixed. So the chamber commits a small
`corpus/` (an incident, an ADR, a runbook) and `task test` mines it fresh, runs a fixed set of
queries, and asserts each returns its matching drawer, printing a PASS/FAIL matrix in the same
shape as `shared/redteam/run-validation.sh`. No microphone, no network, no LLM: a headless
check any future change can be run against. (Same design rule as any non-deterministic
chamber: pin the inputs, assert the outputs.)

## Embeddings: local by default

Out of the box the embedder is the bundled `all-MiniLM-L6-v2` (~30 MB ONNX), which is CPU-only
and needs no server. That is what the chamber ships and what `task test` is verified against,
and it is a genuine plus: the memory layer has zero external dependencies, not even the
`local-llm` Ollama server. MemPalace can instead point its embedder at a local Ollama model
(`embeddinggemma` over the OpenAI-compatible endpoint), which keeps everything local while
sharing one model server across chambers; the index has to be rebuilt on a switch because the
vector space changes. That path lives in MemPalace's own config and is deliberately left out of
the task list here: it was not verified on this box, and shipping an unverified command would
be worse than pointing at the upstream docs.

## Wiring into Claude Code

MemPalace ships a first-party MCP server (`mempalace mcp` prints the connect command). Once
added, Claude Code can write and search memories through MCP tools during a normal session.
This chamber keeps that step opt-in and manual: `task mcp` only prints the command, because
adding it edits your global Claude Code config, which is not something a lab task should do to
your machine behind your back.

## An honest read on MemPalace

The tool fits this box on the merits, but its marketing does not survive scrutiny, and you
should know that before adopting it:

- The headline **96.6% recall** is R@5 on bare ChromaDB with `all-MiniLM-L6-v2` and none of the
  wings/rooms/drawers structure. MemPalace's own `BENCHMARKS.md` and an independent critique
  (issue #703) read it as a property of verbatim-storage-plus-good-embeddings, not an
  architectural win; the earlier "100%" was overfit, and end-to-end answer accuracy is ~67%.
- The **58.8k stars** are a real GitHub count on a suspiciously fast curve (roughly five months,
  where comparable projects took years). Inflation is a reasonable inference, not proof.

None of that makes the tool bad; it makes the vendor's claims untrustworthy. Because MemPalace
is MIT and fully offline, the lock-in downside is capped: you can fork it, and nothing leaves
the machine. If the conduct bothers you, `txtai` (Apache-2.0, built-in MCP, fully local) is the
trust-first swap, and `cognee` is the option if you want graph-augmented recall and can absorb
a write-time LLM cost.

## How this differs from local-sre-copilot

`local-sre-copilot` is a multi-agent LangGraph supervisor that does RAG over a fixed runbook
corpus to *diagnose a simulated incident*. This chamber is not an agent and not a diagnosis: it
is the *memory substrate itself*, tested in isolation, and designed to be wired into a real
agent (Claude Code) over MCP. One is an application that happens to retrieve; this is the
retrieval layer as the object under test.
