# The SRE copilot, end to end

How the on-call copilot in this chamber works: a local RAG + MCP + multi-agent
stack that diagnoses an incident, retrieves the runbook, and proposes a fix.

## The one idea

An on-call engineer facing "checkout is throwing 500s" hops between metrics,
logs, and a wiki of runbooks. The copilot does that legwork with three cooperating
LLM agents and a set of tools, and returns a grounded, cited answer. Everything
runs locally: the model (Ollama), the vector store (embedded Qdrant), the tool
server (MCP), and the agents.

## The pieces

### Local model serving (Ollama)
Ollama serves two models: `qwen2.5:7b` for chat and tool-calling (chosen because
it drives tools reliably, unlike smaller models) and `nomic-embed-text` for
embeddings. Using Ollama for embeddings too means no `fastembed`/`onnxruntime`
binary wheels, which matters on NixOS.

### RAG (retrieval)
`app/rag.py` chunks the markdown corpus (runbooks, postmortems, architecture),
embeds each chunk with Ollama, and stores the vectors in **Qdrant running
embedded** (qdrant-client local mode, on-disk) - no server process. Retrieval is
a similarity search over that store. The on-disk store is single-writer, which
drives a key design choice below.

### MCP (the tool + store owner)
`app/mcp_server.py` is a **FastMCP** server (streamable-http on :8808). It is the
single owner of the Qdrant store and the single provider of every tool:

- `search_runbooks` - RAG retrieval over the corpus.
- `query_metrics`, `search_logs`, `get_service_health` - simulated SRE telemetry
  that returns a deterministic incident (a checkout outage from a payments
  deploy), so the flow is reproducible. In production these would query
  Prometheus, the log backend, and the health checks.

Making the MCP server own Qdrant avoids two processes fighting over the
single-writer store, and it decouples the tools from the agents: the tools are a
protocol boundary, not in-process functions. `langchain-mcp-adapters` turns them
into LangChain tools the agents call.

### Multi-agent supervisor (LangGraph)
`app/agents.py` builds a LangGraph graph that runs three specialists in turn,
each with its own tools and role, sharing accumulated findings:

- **Diagnostician** - uses `query_metrics`, `search_logs`, `get_service_health`
  to establish what is happening and the trigger.
- **Knowledge** - uses `search_runbooks` to find the mitigation and prior
  postmortem, citing sources.
- **Writer** - synthesizes a short, grounded, cited incident answer.

A single ReAct agent with all the tools also exists (`single_agent`) and is the
minimal working version; the supervisor is the "complex" upgrade with role
specialization.

### API (FastAPI)
`app/api.py` builds the supervisor once at startup and serves `POST /chat`. It
never touches Qdrant directly - it talks to the MCP server over HTTP, which owns
the store.

## Two gotchas worth knowing

- **NixOS binary wheels**: langchain drags in compiled wheels (pydantic-core,
  ...) that need libstdc++/zlib at runtime. NixOS has no FHS linker, so the flake
  shellHook exports `LD_LIBRARY_PATH`, and `UV_PYTHON_DOWNLOADS=never` keeps uv on
  the nix Python. Without this, nothing imports.
- **MCP tools are async-only**: they raise "StructuredTool does not support sync
  invocation" if a node calls `.invoke()`. The graph nodes must be `async` and
  use `ainvoke`; the API invokes the graph with `ainvoke`.

## The local-model tradeoff

Inference is CPU-only unless you have a GPU, so a query runs seconds-to-minutes
(the multi-agent flow makes several LLM calls). The bar here is "the pipeline
executes and returns a grounded, cited answer", not answer quality - LLM output
is non-deterministic. The model is pluggable: set `COPILOT_CHAT_MODEL` and point
the Ollama base URL at an OpenAI-compatible proxy to trade the key for speed.

## Mapping to a real deployment

| Chamber piece | Production equivalent |
|---|---|
| `query_metrics` | Prometheus / the metrics chamber (`kind-slo-error-budget`) |
| `search_logs` | Loki / Elasticsearch (`kind-elk`) |
| `get_service_health` | Icinga check states (`kind-icinga`) |
| `search_runbooks` | RAG over the real runbook/postmortem wiki |
| Ollama | a hosted model endpoint, or Ollama on a GPU node |
| embedded Qdrant | a Qdrant service or another vector DB |

## The one-paragraph version

This chamber is a local SRE copilot: Ollama serves a tool-calling model and an
embedding model, a runbook corpus is embedded into an on-disk Qdrant store, and a
FastMCP server owns that store and exposes runbook search plus simulated
telemetry as MCP tools. `langchain-mcp-adapters` loads those tools into a
LangGraph multi-agent supervisor - Diagnostician, Knowledge, Writer - that
diagnoses an incident, retrieves the runbook, and writes a grounded, cited
answer, served over a FastAPI `/chat` endpoint. Swap the simulated tools for
Prometheus/Loki/Icinga and the model for a hosted endpoint, and it is the real
thing.
