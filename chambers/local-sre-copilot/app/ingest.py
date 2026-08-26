"""Ingest the corpus into the Qdrant store. Run once before starting the MCP
server (they share the single-writer on-disk store)."""
from . import rag


def main() -> None:
    n = rag.build_store()
    print(f"ingested {n} chunks into the '{rag.config.COLLECTION}' collection")


if __name__ == "__main__":
    main()
