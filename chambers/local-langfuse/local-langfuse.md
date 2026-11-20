# Watching a local LLM with Langfuse

An LLM call is the hardest kind of function to debug: the output is non-deterministic, the
interesting failures are semantic rather than exceptions, and the cost and latency are real but
invisible from the call site. Observability for LLM apps is the practice of recording each call
as structured data - the exact prompt, the response, the model and its parameters, token counts,
latency, and how calls nest into a larger run - so you can inspect, compare, and measure instead
of guessing. Langfuse is an open-source tool for exactly that, and it self-hosts, which is why it
fits here: the traces of your local model stay on the same machine the model runs on.

## Why a trace tool needs six containers

A single LLM call looks trivial to store. A production trace store is not, and Langfuse v3/v4
splits the job across services that each do one thing well:

- **Postgres** holds the transactional metadata: users, projects, API keys, datasets, prompts.
  Small, relational, consistency-critical.
- **ClickHouse** holds the traces and observations themselves. Trace data is append-heavy and
  read with analytical queries ("p95 latency for this model last week", "every trace with cost
  over a threshold"), which is a column store's home turf, not Postgres's. This is also the
  container that wants the most memory.
- **Redis** is the ingestion queue. Writes do not go straight to ClickHouse; they are buffered
  so a burst of spans does not block the caller or overwhelm the column store.
- **MinIO** is S3-compatible blob storage for the raw ingestion events and any media. Large
  payloads live here rather than bloating the databases.
- **web** serves the UI and API; **worker** drains the Redis queue and writes batches into
  ClickHouse.

The write path is therefore SDK → web (ingest) → MinIO/Redis → worker → ClickHouse, and a read is
served from ClickHouse. `task test` asserts exactly that path end to end: it emits a span and does
not pass until the span is queryable back out of the store.

## The wrapper is the whole ergonomic

Instrumenting a call should not mean rewriting it. Because the [`local-llm`](../local-llm/) server
speaks the OpenAI wire format, tracing it is a one-line import swap:

```python
from langfuse.openai import openai   # instead of: import openai
```

The wrapper is a drop-in around the OpenAI client. Every `chat.completions.create` it sees becomes
a `generation` observation with the inputs, outputs, model, and usage attached, nested under
whatever span is active. The same trick works for any OpenAI-compatible endpoint, which is the
same property that makes the local-llm chamber useful in the first place: one wire format, many
tools, no bespoke integration.

## v4 runs ingestion-first

Langfuse v4 defaults to `events_only` write mode, and it is worth understanding because it changes
what the API does. Ingestion is event-sourced over OpenTelemetry: the SDK ships OTLP spans, they
are written as immutable events, and the queryable trace/observation tables are derived from them.
The visible consequence is that the **legacy** read endpoints from v3 (`GET /api/public/traces`)
now return 404, and reads go through the v2 API (`GET /api/public/v2/observations`). The UI renders
traces in full from the event store; the v2 read API, in this release, is still filling in field
coverage, so this chamber uses it as an existence check and points you at the UI for the full
picture.

## Headless seeding makes it a lab, not a setup chore

A stack you have to click through a signup wizard to use is not reproducible. This chamber seeds
the organization, project, user, and a fixed pair of API keys through `LANGFUSE_INIT_*` environment
variables, so the moment `task up` reports healthy there is a project to send traces to and keys to
send them with. The keys and every other secret are generated once into a gitignored `.env` and
reused, because they are bound to the data already written: the `ENCRYPTION_KEY` decrypts rows in
Postgres, so rotating it against a populated volume is a silent corruption, not a fresh start. The
stack treats the secrets and the volumes as one unit - kept together, wiped together.
