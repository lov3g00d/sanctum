# Chamber: local-llm

A playground for running an LLM on your own machine, with no cloud, no API keys, and no
per-token bill. Ollama serves a local model behind an OpenAI-compatible API; from there you
chat with it, drive it from any OpenAI client, watch a tool-calling round-trip, and measure
what it actually costs on this hardware.

This chamber is the *substrate* (serve a model, hit the endpoint, swap models, benchmark).
The [`local-sre-copilot`](../local-sre-copilot/) chamber is the *application* built on top of
the same server (RAG over runbooks, MCP tools, a multi-agent supervisor).

## What it demonstrates

- A local model served behind the same `/v1/chat/completions` wire format OpenAI uses, so any
  OpenAI SDK, agent, or UI points at `localhost` unchanged.
- Tool calling end to end: the model emits a structured function request, you run it, feed the
  result back, and it answers with real data. This is the primitive under every coding agent.
- Picking a model for your hardware: a curated CPU-friendly set, a side-by-side compare, and a
  benchmark that reports the real prefill/decode tokens per second on this box.

## Prerequisites

- The repo toolchain: `nix develop` from the repo root (provides `ollama`, `jq`, `curl`).
- Disk for the models (the default `qwen3:8b` is ~5 GB; see the table below).
- No GPU is required. See [`local-llm.md`](local-llm.md) for what to expect without one.

## Stand up

```sh
cd chambers/local-llm
task up            # start the ollama server (if not already running) + pull qwen3:8b
task chat          # talk to it
```

Then explore:

```sh
task api           # prove the OpenAI-compatible endpoint with curl
task tools         # watch a full tool-calling round-trip
task bench         # tokens/sec on this machine
task compare A=qwen3:4b B=qwen3:8b
task status        # server version, installed models, what is loaded
```

Every task takes `MODEL=<tag>`, e.g. `task chat MODEL=qwen2.5-coder:7b`.

## Curated models (CPU-friendly)

| Tag | Size | Use |
|-----|------|-----|
| `qwen3:4b` | ~2.5 GB | fast, low latency |
| `qwen3:8b` | ~5 GB | default; best balance for chat/reasoning |
| `qwen2.5-coder:7b` | ~4.7 GB | coding |
| `gemma3:4b` | ~3.3 GB | alternative small general model |
| `qwen3:30b-a3b` | ~19 GB | Mixture-of-Experts (~3B active); large-model quality at small-model speed, if you can spare the RAM |

`task pull` grabs the first four in one go.

## Tear down

```sh
task down          # stop the server only if this chamber started it
```

Pulled models stay on disk. Remove one with `ollama rm <tag>`; list them with `task status`.
