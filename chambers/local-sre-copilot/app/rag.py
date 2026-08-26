"""RAG layer: ingest the runbook corpus into an embedded Qdrant store and open a
retriever over it. Embeddings come from Ollama (nomic-embed-text), so no binary
embedding wheels are needed. The on-disk Qdrant store is single-writer, so only
one process opens it at a time (ingest, then the MCP server)."""
from pathlib import Path

from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings
from langchain_qdrant import QdrantVectorStore
from langchain_text_splitters import RecursiveCharacterTextSplitter
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams

from . import config


def embeddings() -> OllamaEmbeddings:
    return OllamaEmbeddings(base_url=config.OLLAMA_BASE_URL, model=config.EMBED_MODEL)


def _load_chunks() -> list[Document]:
    splitter = RecursiveCharacterTextSplitter(chunk_size=800, chunk_overlap=120)
    docs: list[Document] = []
    for md in sorted(Path(config.CORPUS_DIR).glob("*.md")):
        text = md.read_text(encoding="utf-8")
        for chunk in splitter.split_text(text):
            docs.append(Document(page_content=chunk, metadata={"source": md.name}))
    return docs


def build_store() -> int:
    """Ingest the corpus. Opens the store exclusively, writes, and closes."""
    chunks = _load_chunks()
    emb = embeddings()
    dim = len(emb.embed_query("dimension probe"))
    Path(config.QDRANT_PATH).mkdir(parents=True, exist_ok=True)
    client = QdrantClient(path=config.QDRANT_PATH)
    try:
        if client.collection_exists(config.COLLECTION):
            client.delete_collection(config.COLLECTION)
        client.create_collection(
            config.COLLECTION,
            vectors_config=VectorParams(size=dim, distance=Distance.COSINE),
        )
        store = QdrantVectorStore(
            client=client, collection_name=config.COLLECTION, embedding=emb
        )
        store.add_documents(chunks)
    finally:
        client.close()
    return len(chunks)


def open_store() -> QdrantVectorStore:
    """Open the store for reading. Caller owns the underlying client for the
    process lifetime (the MCP server holds a single instance)."""
    client = QdrantClient(path=config.QDRANT_PATH)
    return QdrantVectorStore(
        client=client, collection_name=config.COLLECTION, embedding=embeddings()
    )
