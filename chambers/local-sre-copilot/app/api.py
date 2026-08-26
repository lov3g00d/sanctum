"""FastAPI surface for the SRE copilot. Builds the multi-agent supervisor once at startup
(it connects to the MCP server over HTTP; the MCP server owns Qdrant, so the API
never touches the store directly). Ingestion is a separate task, not an endpoint,
because the on-disk store is single-writer."""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from langchain_core.messages import HumanMessage
from pydantic import BaseModel

from . import agents

_graph = None


class ChatRequest(BaseModel):
    question: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _graph
    _graph = await agents.build_supervisor()
    yield


app = FastAPI(title="SRE on-call copilot", description="SRE on-call copilot", lifespan=lifespan)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/chat")
async def chat(req: ChatRequest):
    result = await _graph.ainvoke({"messages": [HumanMessage(req.question)], "findings": ""})
    return {
        "answer": result["messages"][-1].content,
        "findings": result.get("findings", ""),
    }
