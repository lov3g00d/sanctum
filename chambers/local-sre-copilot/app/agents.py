"""Agents for the SRE copilot. A single ReAct agent (proves the local model can
drive the MCP tools) and a hand-rolled multi-agent supervisor that routes between
an incident Diagnostician and a runbook Knowledge specialist, then a Writer
synthesizes a grounded, cited answer. All tools come from the MCP server."""
from typing import Annotated, TypedDict

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_ollama import ChatOllama
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt import create_react_agent

from . import config

COPILOT_SYS = (
    "You are an SRE on-call copilot. You are calm, precise, and you cite "
    "evidence. Use the tools to gather metrics, logs, health, and runbook guidance "
    "before answering. Never invent metric values or runbook steps."
)
DIAG_SYS = (
    "You are the Diagnostician. Use query_metrics, search_logs, and "
    "get_service_health to establish what is happening and the likely trigger. "
    "Report the concrete evidence (numbers, log lines, deploy timing)."
)
KNOW_SYS = (
    "You are the Knowledge specialist. Use search_runbooks to find the relevant "
    "runbook and any prior postmortem. Report the mitigation steps and cite the "
    "source document names in [brackets]."
)
WRITER_SYS = (
    "You are an SRE on-call copilot. Given the diagnostic evidence and runbook findings, write a "
    "short incident answer: (1) what is happening, (2) the likely root cause with "
    "evidence, (3) the recommended remediation, citing runbook/postmortem sources "
    "in [brackets]. Be concise. Do not invent facts not in the findings."
)


def make_llm(**kw) -> ChatOllama:
    return ChatOllama(
        base_url=config.OLLAMA_BASE_URL, model=config.CHAT_MODEL, temperature=0, **kw
    )


async def get_tools():
    client = MultiServerMCPClient(
        {"sre-copilot": {"url": config.MCP_URL, "transport": "streamable_http"}}
    )
    return await client.get_tools()


async def single_agent():
    """One ReAct agent with all MCP tools (rung E)."""
    tools = await get_tools()
    return create_react_agent(make_llm(), tools, prompt=COPILOT_SYS)


class State(TypedDict):
    messages: Annotated[list, add_messages]
    findings: str


def _question(state: State) -> str:
    for m in state["messages"]:
        if isinstance(m, HumanMessage):
            return m.content
    return state["messages"][-1].content


async def build_supervisor():
    """Multi-agent supervisor: Diagnostician -> Knowledge -> Writer, each a
    specialist agent with its own MCP tools, sharing accumulated findings."""
    tools = {t.name: t for t in await get_tools()}
    llm = make_llm()
    diag = create_react_agent(
        llm,
        [tools["query_metrics"], tools["search_logs"], tools["get_service_health"]],
        prompt=DIAG_SYS,
    )
    know = create_react_agent(llm, [tools["search_runbooks"]], prompt=KNOW_SYS)

    # The MCP tools are async-only, so the specialist nodes must be async and
    # use ainvoke (the graph is invoked with ainvoke by the API).
    async def diagnostician(state: State):
        res = await diag.ainvoke({"messages": [HumanMessage(_question(state))]})
        return {"findings": f"[Diagnostician]\n{res['messages'][-1].content}\n"}

    async def knowledge(state: State):
        q = _question(state) + "\n\nDiagnostic evidence:\n" + state.get("findings", "")
        res = await know.ainvoke({"messages": [HumanMessage(q)]})
        return {"findings": state.get("findings", "") + f"[Knowledge]\n{res['messages'][-1].content}\n"}

    async def writer(state: State):
        res = await llm.ainvoke([
            SystemMessage(WRITER_SYS),
            HumanMessage(f"Question:\n{_question(state)}\n\nFindings:\n{state['findings']}"),
        ])
        return {"messages": [AIMessage(res.content)]}

    g = StateGraph(State)
    g.add_node("diagnostician", diagnostician)
    g.add_node("knowledge", knowledge)
    g.add_node("writer", writer)
    g.add_edge(START, "diagnostician")
    g.add_edge("diagnostician", "knowledge")
    g.add_edge("knowledge", "writer")
    g.add_edge("writer", END)
    return g.compile()
