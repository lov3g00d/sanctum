# Chamber: local-llm

A playground for running an LLM on your own machine, with no cloud, no API keys, and no
per-token bill. Ollama serves a local model behind an OpenAI-compatible API; from there you
chat with it or drive it via the Claude Code CLI.

This chamber is the *substrate* (serve a model, hit the endpoint, swap models).
The [`local-sre-copilot`](../local-sre-copilot/) chamber is the *application* built on top of
the same server (RAG over runbooks, MCP tools, a multi-agent supervisor).

## What it demonstrates

- A local model served behind the same `/v1/chat/completions` wire format OpenAI uses, so any
  OpenAI SDK, agent, or UI points at `localhost` unchanged.
- Driving Claude Code locally: no cloud, no API key, and no proxy - it just
  points at `localhost` instead of Anthropic.

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
task status        # server version, installed models, what is loaded
```

Every task takes `MODEL=<tag>`, e.g. `task chat MODEL=qwen2.5-coder:7b`.

## Drive Claude Code with the local model

Ollama speaks the Anthropic Messages API natively (v0.14+), so the Claude Code CLI
can run against a local model with no cloud, no API key, and no proxy - it just
points at `localhost` instead of Anthropic.

```sh
task claude                        # launch Claude Code on the default model, all local
task claude -- "explain this repo" # one-shot
task claude MODEL=qwen2.5:14b      # a stronger tool-caller
```

The `claude` task just points Claude Code's `ANTHROPIC_BASE_URL` at the server and
sets the model to the same `MODEL` var `task chat` uses - no derived model, no
proxy. The larger context its agent loop needs is set once for the whole server
(`OLLAMA_CONTEXT_LENGTH` in the Taskfile), so it applies after `task up`. Inside,
`/status` shows the base URL - confirm it reads `http://127.0.0.1:11434`, not the cloud.

Reality check: tool-calling reliability is the bottleneck on small models
(`qwen3:8b` ~50%, `qwen2.5:14b` ~96%), and each turn is slow on CPU because Claude
Code sends a large system prompt. Good for learning the plumbing, not a replacement
for hosted Claude on real work - `task chat` is far snappier for plain local chat.

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
