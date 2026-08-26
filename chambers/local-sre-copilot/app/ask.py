"""CLI: ask the copilot a question via the running API."""
import sys

import httpx

API = "http://127.0.0.1:8809/chat"


def main() -> None:
    question = " ".join(sys.argv[1:]) or "checkout is throwing 500s, diagnose it and tell me the fix"
    print(f"Q: {question}\n")
    resp = httpx.post(API, json={"question": question}, timeout=900)
    resp.raise_for_status()
    print(resp.json()["answer"])


if __name__ == "__main__":
    main()
