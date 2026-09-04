# Running an LLM locally

The pitch for local inference is simple: your prompts and data never leave the machine, there
is no API key and no per-token bill, and it works on a plane. The catch is that you trade a
frontier hosted model for whatever your own hardware can hold and run at a tolerable speed.
This note is about making that trade deliberately.

## Two numbers decide everything: memory and throughput

**Memory sets what you can load.** A model's weights have to fit in memory to run well. A
4-bit-quantized model needs roughly `params x 0.5 GB` plus headroom for the KV cache (which
grows with context length). So an 8B model is ~5 GB, a 14B is ~9 GB, a 30B is ~19 GB. On this
box (30 GB RAM, no GPU) memory is not the tight constraint.

**Throughput sets what it feels like.** Decode speed (tokens per second while it writes) is
dominated by memory bandwidth and whether there is an accelerator. Three regimes, fastest
first:

- **Discrete/unified GPU** - weights live in fast VRAM (or Apple's unified memory, shared by
  CPU and GPU with no PCIe copy). Tens to low hundreds of tok/s.
- **CPU only** - what this machine is. Weights sit in system RAM and the CPU does the matmuls.
  Expect single to low-double-digit tok/s for a 7-8B model, and it drops roughly linearly as
  the model grows. Usable for chat and short agent turns; slow for long generations.

`task bench` prints the real prefill and decode numbers for whatever model you point it at, so
you are deciding on measured behaviour rather than a benchmark table from someone else's rig.

## The CPU sweet spot: a small model, or a big MoE

Two ways to get good answers without a GPU:

1. **A dense 7-8B model** (`qwen3:8b`, `qwen2.5-coder:7b`). Every parameter runs on every
   token, so quality is solid and speed is bounded by the 8B compute.
2. **A Mixture-of-Experts model** (`qwen3:30b-a3b`). 30B total parameters, but a router
   activates only ~3B per token. You pay 30B of *memory* (~19 GB at 4-bit, which this box has)
   but only ~3B of *compute per token*, so it runs at roughly small-model speed while drawing
   on a much larger parameter pool. On a memory-rich, GPU-poor machine this is the most
   interesting option - free up RAM first, then `task chat MODEL=qwen3:30b-a3b`.

## Why "OpenAI-compatible" is the whole game

Ollama exposes `/v1/chat/completions` at `http://localhost:11434/v1`, byte-compatible with
OpenAI's API. That one fact is what makes local models useful rather than a novelty: every
OpenAI SDK, every coding agent, and chat UIs like Open WebUI take a base URL and an API key,
so you point them at localhost with a throwaway key and they work unchanged. `task api` shows
the raw call. To drive an editor agent, set its provider to "OpenAI compatible", base URL
`http://localhost:11434/v1`, and the model tag from `task status`.

## Tool calling is the agent primitive

A model that only emits text can advise but not act. Tool calling is the structured protocol
that lets it *request* an action: you advertise functions (name, description, JSON-schema
params), the model replies with a call and arguments, your code runs it, and you feed the
result back for a final answer. `task tools` walks one full round-trip against a local
`get_weather` function. Everything an "agentic" coding tool does - edit a file, run a test,
read output, iterate - is this loop repeated. Note that qwen3 is a hybrid reasoning model; the
demo sets `think:false` so the tool call is not buried under a reasoning monologue.

## Quantization, briefly

Local models are almost always quantized: weights stored at 4-8 bits instead of 16, trading a
little quality for a large drop in memory and a speed gain. Ollama's default tag (e.g.
`qwen3:8b`) is a 4-bit build, which is the right default. Only reach for a higher-precision
tag if you can measure a quality problem and have the memory to spare.

## On Apple Silicon

This chamber targets the Linux box the repo runs on, so it uses Ollama and CPU-sized models.
The idea for it came from a walkthrough of the same concepts on a MacBook Pro M5 Max ("I
Cancelled ChatGPT, Cursor, and Midjourney This Week", Mac O'Clock, 2026). The Apple path
differs in the parts that are hardware-specific: on Apple Silicon the fast route is the
[MLX](https://github.com/ml-explore/mlx) framework (via [LM Studio](https://lmstudio.ai) or
`mlx-lm`), which runs on the GPU against unified memory. The transferable lesson is the one
above - unified memory is what lets a MoE model punch above its active-parameter weight - and
it is exactly why an Apple machine with enough memory is a strong local-inference box. The
tooling names change; the OpenAI-compatible-endpoint and tool-calling patterns in this chamber
do not.
