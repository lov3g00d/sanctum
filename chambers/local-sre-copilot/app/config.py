import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
CHAT_MODEL = os.environ.get("COPILOT_CHAT_MODEL", "qwen2.5:7b")
EMBED_MODEL = os.environ.get("COPILOT_EMBED_MODEL", "nomic-embed-text")

CORPUS_DIR = Path(os.environ.get("COPILOT_CORPUS_DIR", ROOT / "corpus"))
QDRANT_PATH = os.environ.get("COPILOT_QDRANT_PATH", str(ROOT / "data" / "qdrant"))
COLLECTION = "runbooks"

# The MCP server (owns the Qdrant store and exposes every tool) runs as a
# streamable-http service; the agents connect to it here.
MCP_URL = os.environ.get("COPILOT_MCP_URL", "http://127.0.0.1:8808/mcp")
MCP_HOST = os.environ.get("COPILOT_MCP_HOST", "127.0.0.1")
MCP_PORT = int(os.environ.get("COPILOT_MCP_PORT", "8808"))
