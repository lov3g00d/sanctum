# k8sgpt on a local model

k8sgpt is two things stacked. Underneath is a set of **deterministic analyzers**: code that reads
the cluster and knows that a pod stuck in `ImagePullBackOff`, a service with no endpoints, or a PVC
that never binds is a problem. On top is an optional **`--explain`** pass that hands those findings
to an LLM to phrase in plain English and suggest a fix. This chamber runs the analyzers against a
kind cluster and points the explain pass at the local Ollama server.

## Why this split fits a CPU-only box

The expensive, model-quality-sensitive work in most "AI ops" tools is a multi-step agent loop, which
is where a small quantized model on a GPU-less machine struggles. k8sgpt does not work that way: the
analysis is done in Go before any token is generated, and the model only sees a short, structured
problem to rephrase. That is a single-pass summarization task, which a 7-8B model handles well on
CPU. So the useful, correct part (what is broken) never depends on the model, and the model only
improves the presentation (how to think about the fix).

That shape is also why the chamber's deterministic test uses `analyze -o json` with no `--explain`:
the pass/fail gate asserts the analyzers found the two planted faults, which is reproducible and
needs no model. `--explain` is the interactive layer on top, demoed but not asserted.

## How the local backend is wired

k8sgpt ships a native `ollama` backend. The chamber configures it into a chamber-local config file
rather than the global one:

```sh
k8sgpt --config .run/k8sgpt.yaml auth add \
  --backend ollama --model qwen2.5:7b --baseurl http://localhost:11434
k8sgpt --config .run/k8sgpt.yaml --kubecontext kind-k8sgpt analyze -n k8sgpt-demo --backend ollama --explain
```

The baseurl is the Ollama server root, not the OpenAI-compatible `/v1` path: k8sgpt's `ollama`
backend calls the native `/api/generate`, so `http://localhost:11434/v1` 404s. Two more deliberate
choices keep the lab from leaking into your machine: `--config .run/k8sgpt.yaml` keeps the backend
definition inside the chamber, and `--kubecontext kind-k8sgpt` names the target cluster on every call
instead of relying on whatever your current kube-context happens to be. k8sgpt runs on the host and
reaches Ollama on `localhost`, so no in-cluster networking is involved.

## The planted faults

`k8s/broken.yaml` applies two failures with distinct analyzers:

- a Deployment whose image tag does not exist, so its pod wedges in `ImagePullBackOff` (Pod analyzer);
- a Service whose selector matches no pods, so it has no endpoints (Service analyzer).

`task fix` swaps the deployment to a real image and re-runs the analysis, which is the honest way to
show the tool is reading live state rather than replaying a canned report.

## Three ways to consume it: CLI, MCP, operator

The analyze/explain split above is the CLI. The same engine is reachable two other ways:

- **MCP** (`k8sgpt serve --mcp`): k8sgpt exposes its tools (`analyze`, `cluster-info`, `get-logs`,
  `get-resource`, `list-events`, `list-namespaces`, `list-resources`, filters) over the Model
  Context Protocol, so Claude Code can drive the cluster read/analysis directly in a session. One
  quirk: `serve` always binds a gRPC port (8080 by default) and a metrics port even in MCP mode, so
  the chamber pins `--port 8090 --metrics-port 8091` to keep concurrent sessions from colliding.

- **Operator** (`k8sgpt-operator`, Helm-installed): the in-cluster form. A `K8sGPT` custom resource
  configures it, and it scans continuously, writing each finding as a `Result` CRD you can
  `kubectl get` or wire alerts off. This is the shape you would actually run in a cluster, versus the
  CLI you run at a laptop.

## The operator's two wrinkles (both real, both handled)

1. **No native `ollama` backend yet.** The operator chart's CRD only accepts `openai`, `localai`,
   and friends, not the CLI's `ollama` value. `localai` is the right choice because it is
   OpenAI-compatible and Ollama serves an OpenAI-compatible `/v1` endpoint.

2. **The operator can't reach the host's Ollama.** It runs inside kind, and on this machine the
   NixOS firewall blocks the kind bridge from reaching the host's `:11434` (confirmed: even the kind
   node times out to the bridge gateway). So the chamber runs the operator **analysis-only**
   (`ai.enabled: false`), which needs no model and still produces the full `Result` set. To get
   LLM-explained results from the operator you would either open the host firewall for the kind
   bridge (a privileged `nixos-rebuild`, deliberately not automated here) and set
   `ai.enabled: true` with `baseUrl: http://<kind-gateway>:11434/v1` after binding Ollama to
   `0.0.0.0`, or run an Ollama inside the cluster and point `baseUrl` at its Service. The
   analysis-only default is the honest, reproducible one; the findings are the deterministic part
   anyway.

## Where it sits among the chambers

`local-llm` is the model server this borrows for `--explain`. `local-sre-copilot` is a multi-agent
supervisor that reasons over simulated telemetry. This chamber is neither: it is a real, if small,
Kubernetes control-plane read by a purpose-built analyzer, with the model used only for phrasing. It
is the smallest honest example of "AI for SRE" that actually runs well without a GPU.
