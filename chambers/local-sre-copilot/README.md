# Chamber: local-sre-copilot

> **Status: prototype.** A local learning stack, not a production deployment.
> The architecture (RAG + MCP + multi-agent) is production-real; the runtime
> (single-machine, embedded Qdrant, CPU Ollama, simulated telemetry, no auth) is
> lab-grade. The path to prod-ish is a containerized deploy (real Qdrant, GPU or
> hosted model, secrets, auth, human-in-the-loop) - see "Deploying" below.
>
> **Environment:** a `nix develop` devshell provides the runtimes (`ollama`,
> `uv`, `python`); the fast-moving AI libraries are pinned in a `uv` venv. No
> cloud, no API key.

An SRE on-call copilot, fully local. Ask it about an incident and a **LangGraph
multi-agent team** diagnoses it from telemetry, retrieves the relevant runbook
(RAG), and proposes a remediation, citing its sources.

Every AI piece runs on your machine - a local LLM (Ollama), an embedded vector
store (Qdrant), an MCP tool server, and the agents - so there is no API key and
no cloud dependency.

## Concepts

If the terms below are new, here is what each one is and why it is here. Each
layer fixes a limitation of the layer below it.

- **LLM** - the text-in, text-out model (`qwen2.5:7b`). On its own it knows
  nothing about your systems and cannot act. **Ollama** runs it locally over
  HTTP, no API key. Everything else exists to make the LLM *grounded* (know your
  facts) and *capable* (take actions).
- **Embeddings** - a model (`nomic-embed-text`) that turns text into a vector
  where similar meanings are close together, so you can search by meaning, not
  keywords.
- **Vector database (Qdrant)** - stores those vectors and finds the nearest ones
  to a query fast. Runs embedded (in-process, on disk) here.
- **RAG (Retrieval-Augmented Generation)** - the pattern that fixes "the LLM does
  not know your runbooks". Embed your docs up front; at question time embed the
  question, retrieve the closest chunks, and put them in the prompt so the model
  answers *from your documents* and can cite them. Here: runbooks -> Qdrant ->
  `search_runbooks`.
- **Tool calling** - the LLM deciding to call `query_metrics(service="checkout")`
  instead of answering directly. You expose tools with schemas; the model picks
  one; your code runs it and feeds the result back. This is how it *acts*.
- **Agent (ReAct)** - an LLM in a loop: reason -> act (call a tool) -> observe ->
  repeat, until it can answer. The Diagnostician is a ReAct agent.
- **LangChain** - standard interfaces for LLM apps (models, prompts, tools,
  retrievers) so you do not hand-roll them. Provides `ChatOllama`, the Qdrant
  retriever, and the tool abstractions.
- **LangGraph** - stateful, multi-step orchestration. Where an agent is a loop, a
  LangGraph *graph* has nodes (steps/agents) and edges (what runs next) carrying
  shared state. The supervisor is a LangGraph graph.
- **Multi-agent / supervisor** - split the work across specialists (each with a
  focused role and its own tools) coordinated by a supervisor, instead of one
  agent juggling everything. Here: Diagnostician, Knowledge, Writer.
- **MCP (Model Context Protocol)** - an open standard for exposing tools and data
  to LLMs over a protocol instead of hardcoding them per app, so tools become a
  decoupled boundary any agent framework can use. `mcp_server.py` publishes the
  tools; `langchain-mcp-adapters` loads them into the agents. **FastMCP** is the
  Python SDK the server uses.

```
  LLM (Ollama) + embeddings + vector DB     raw capability
          │
  RAG (ground it) + tool calling (empower it)
          │
  Agent (ReAct loop)                        one LLM using tools
          │
  LangGraph graph -> multi-agent supervisor  orchestrated specialists
          │
  MCP                                       tools exposed over a standard protocol
```

## Architecture

```
  question ──▶ FastAPI (:8809) ──▶ Supervisor (LangGraph)
                                     │
                        ┌────────────┼────────────┐
                        ▼            ▼             ▼
                 Diagnostician    Knowledge      Writer
                 (metrics/logs/   (runbook RAG)  (grounded,
                  health)                          cited answer)
                        └────────────┬────────────┘
                                     ▼
                       MCP server (:8808, FastMCP)  ──▶ Qdrant (embedded)
                       tools: search_runbooks,           + Ollama embeddings
                       query_metrics, search_logs,
                       get_service_health
```

- **Ollama** serves the chat/tool-calling model (`qwen2.5:7b`) and the embedding
  model (`nomic-embed-text`) locally.
- **Qdrant** runs embedded (qdrant-client local mode, on-disk) - no server.
- The **MCP server** (FastMCP, streamable-http) owns the Qdrant store and exposes
  every tool: runbook search (RAG) and simulated SRE telemetry. In production
  those telemetry tools would query Prometheus, the log backend, and the health
  checks; here they return a deterministic incident so the flow is reproducible.
- **`langchain-mcp-adapters`** loads the MCP tools into the LangGraph agents, so
  the tools are decoupled behind the protocol.
- The **supervisor** runs three specialists in turn (Diagnostician -> Knowledge
  -> Writer), sharing accumulated findings.

## Components

### Runtimes (from the flake / venv)
| Component | Purpose | How it works |
|---|---|---|
| **Ollama** | Local model server | Serves `qwen2.5:7b` (chat + tool-calling) and `nomic-embed-text` (embeddings) over HTTP on `:11434`. Everything that needs a model or a vector calls it. No API key. |
| **Qdrant (embedded)** | Vector store | Runs in-process via `qdrant-client` local mode, persisting to `data/qdrant/`. Single-writer, so exactly one process opens it at a time. No server. |
| **uv venv** | Python AI libraries | `uv` installs the pinned libs (langchain, langgraph, adapters, ...) into `.venv` against the nix Python. |

### Application modules (`app/`)
| Module | Purpose | How it works |
|---|---|---|
| `config.py` | Central config | Model names, ports, and paths, all overridable via `COPILOT_*` env vars. |
| `rag.py` | The RAG layer | `build_store()` chunks the corpus, embeds each chunk with Ollama, and writes vectors to Qdrant; `open_store()` opens it for retrieval. |
| `ingest.py` | Ingest CLI | Runs `build_store()`. Run once before serving (it needs exclusive access to the store). |
| `mcp_server.py` | The tool server | A **FastMCP** server on `:8808`. Owns the Qdrant store and exposes the four tools. |
| `agents.py` | The agents | `make_llm()` (ChatOllama), `get_tools()` (load MCP tools via the adapter), `single_agent()` (one ReAct agent), and `build_supervisor()` (the multi-agent graph). |
| `api.py` | The HTTP surface | FastAPI on `:8809`. Builds the supervisor once at startup, serves `POST /chat` and `GET /healthz`. Talks to the MCP server over HTTP; never touches Qdrant directly. |
| `ask.py` | CLI client | POSTs a question to `/chat` and prints the answer. |

### The MCP tools (served by `mcp_server.py`)
| Tool | Purpose | How it works |
|---|---|---|
| `search_runbooks(query)` | RAG retrieval | Similarity search over the runbook corpus in Qdrant; returns the top chunks with their source file. |
| `query_metrics(service)` | Metrics | Returns error rate, latency, SLO burn, and recent deploys. Simulated here; would query Prometheus in prod. |
| `search_logs(service)` | Logs | Returns representative error log lines. Simulated; would query Loki/Elasticsearch in prod. |
| `get_service_health(service)` | Health | Returns the service + dependency health/check state. Simulated; would query Icinga/probes in prod. |

### The agents (in the supervisor graph)
| Agent | Purpose | How it works |
|---|---|---|
| **Diagnostician** | Establish what happened | A ReAct agent with the metrics/logs/health tools; reports the concrete evidence and the likely trigger. |
| **Knowledge** | Find the fix | A ReAct agent with `search_runbooks`; retrieves the mitigation and prior postmortem, citing sources. |
| **Writer** | Synthesize | A plain LLM call that turns the shared findings into a short, grounded, cited answer. |
| **Supervisor** | Orchestrate | A LangGraph `StateGraph` that runs Diagnostician -> Knowledge -> Writer, accumulating `findings` in shared state. |

### Corpus (`corpus/`)
Markdown runbooks, a postmortem, and an architecture doc - what the copilot knows.
Edit these and `task ingest` to change its knowledge.

### Scripts (`scripts/`)
`up.sh` and `down.sh` orchestrate the services (start Ollama if needed, pull
models, ingest, start MCP + API), tracking each in its own process group via
pidfiles so they stop cleanly.

### The request flow
`task ask` / `POST /chat` -> the **API** invokes the **supervisor** ->
**Diagnostician** calls the metrics/logs/health tools on the **MCP server** ->
**Knowledge** calls `search_runbooks` (which hits **Qdrant** + **Ollama**
embeddings) -> **Writer** composes the answer with **Ollama** -> a grounded,
cited response returns. Every tool call crosses the MCP protocol boundary, and
the MCP server is the single owner of the vector store.

## Tooling

The runtimes come from the flake (`ollama`, `uv`, `python312`); the fast-moving
AI libraries are pinned in a `uv`-managed venv (`pyproject.toml` + `uv.lock`),
because they move too fast for nixpkgs. NixOS has no FHS linker, so the flake
shellHook sets `LD_LIBRARY_PATH` for the binary wheels.

## Prerequisites

`nix develop` from the repo root. First run pulls the models (~5GB) and boots
Ollama. Inference is CPU-only unless you have a GPU, so answers take
seconds-to-minutes; the model is pluggable to an API by setting
`COPILOT_CHAT_MODEL` and pointing the Ollama base URL at a proxy.

## Use

```sh
cd chambers/local-sre-copilot
task up                       # Ollama + models + ingest + MCP server + API
task ask -- "why is checkout failing after the deploy?"
task demo                     # the sample incident question
task logs                     # tail the MCP + API logs
task down                     # stop the app services (leaves Ollama)
task down-all                 # stop everything including Ollama
```

The API is at `http://127.0.0.1:8809` (`POST /chat`). Edit the corpus under
`corpus/` and `task ingest` to change what the copilot knows.

## What it demonstrates

- **RAG**: chunk + embed a runbook corpus into Qdrant, retrieve by query.
- **MCP**: a FastMCP server exposing tools, consumed by agents through
  `langchain-mcp-adapters` - tools decoupled from the agents.
- **Multi-agent orchestration**: a LangGraph supervisor coordinating specialist
  agents, each with its own tools and role.
- **Local LLM serving**: Ollama for both chat/tool-calling and embeddings.
- **A practical domain**: SRE incident triage - diagnose from telemetry,
  retrieve the runbook, propose the fix - grounded and cited, not a toy chat.

## Deploying

Today the services run locally as background processes (`scripts/up.sh`, managed
by pidfiles) inside the nix devshell. That is a prototype runtime, not a
deployment. To make it prod-ish, the same architecture becomes containers on
Kubernetes:

- API and MCP server as `Deployment`s behind an internal ingress.
- **Qdrant** as a `StatefulSet` instead of the embedded on-disk store.
- The model on a **GPU node pool** (Ollama/vLLM) or a **hosted endpoint** (the
  LLM is env-pluggable); do not bake a multi-GB model into the image.
- Secrets for real telemetry credentials, auth on the endpoints, and a
  human-in-the-loop gate before any remediation action.

It slots onto the `aws-eks` platform (or AKS) as an internal platform service
next to the observability stack, delivered by GitOps. That layer is a follow-up
rung, not built here.

## Reference

[`sre-copilot.md`](sre-copilot.md) is a deep-dive on how the pieces fit (RAG, the MCP
server as the tool + store owner, the multi-agent graph, the local model
tradeoffs, and how each simulated tool maps to a real observability backend).
