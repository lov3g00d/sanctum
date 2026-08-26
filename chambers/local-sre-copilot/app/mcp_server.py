"""The SRE copilot MCP server: the single owner of the Qdrant store and the provider
of every tool the agents use. Exposes runbook search (RAG) plus simulated SRE
telemetry. The telemetry is deterministic and tells a coherent incident story
(a checkout outage caused by a payments deploy) so the multi-agent flow has real
data to reason over. In production these tools would query Prometheus, the log
backend, and the health checks."""
from mcp.server.fastmcp import FastMCP

from . import config, rag

mcp = FastMCP("sre-copilot", host=config.MCP_HOST, port=config.MCP_PORT)

_store = None


def _retriever(k: int = 4):
    global _store
    if _store is None:
        _store = rag.open_store()
    return _store.as_retriever(search_kwargs={"k": k})


@mcp.tool()
def search_runbooks(query: str) -> str:
    """Search the SRE runbooks, postmortems, and architecture docs for guidance
    relevant to the query. Use this to find remediation steps and prior incidents."""
    hits = _retriever().invoke(query)
    if not hits:
        return "No matching runbook content found."
    return "\n\n".join(f"[{h.metadata['source']}]\n{h.page_content}" for h in hits)


@mcp.tool()
def query_metrics(service: str) -> str:
    """Query recent metrics for a service: error rate, latency, and recent deploys."""
    s = service.lower()
    if s in ("checkout", "payments"):
        return (
            f"metrics for {service} (last 15m):\n"
            "- error_ratio_5m: 0.41 (baseline 0.002)\n"
            "- p95_latency_ms: 4200 (baseline 120)\n"
            "- SLO burn rate: 18x (fast-burn threshold 14.4x)\n"
            "- recent deploy: payments v2.7.0 ramped to 100% at 14:09; "
            "error spike began 14:11"
        )
    return (
        f"metrics for {service} (last 15m):\n"
        "- error_ratio_5m: 0.001 (nominal)\n"
        "- p95_latency_ms: 110 (nominal)\n"
        "- SLO burn rate: 0.3x\n"
        "- recent deploy: none"
    )


@mcp.tool()
def search_logs(service: str) -> str:
    """Search recent error logs for a service and return representative lines."""
    s = service.lower()
    if s == "payments":
        return (
            "payments error logs (last 15m):\n"
            "ERROR connection pool exhausted (size=20, waiters=57)\n"
            "ERROR timeout acquiring db connection after 3000ms\n"
            "ERROR fraud-scoring call blocked request for 2900ms"
        )
    if s == "checkout":
        return (
            "checkout error logs (last 15m):\n"
            "ERROR 500 upstream payments returned 500\n"
            "ERROR upstream request to payments timed out"
        )
    return f"{service} logs (last 15m): no errors, nominal traffic."


@mcp.tool()
def get_service_health(service: str) -> str:
    """Get the current health-check state for a service and its dependencies."""
    s = service.lower()
    if s in ("checkout", "payments"):
        return (
            "health:\n- checkout: CRITICAL (dependency errors)\n"
            "- payments: DEGRADED (pool saturation)\n- payments-db: OK"
        )
    return f"health:\n- {service}: OK"


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
