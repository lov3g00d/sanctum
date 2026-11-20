import os
import sys

from langfuse import get_client
from langfuse.openai import openai

ollama_host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
model = os.environ["MODEL"]
project_id = os.environ.get("LANGFUSE_INIT_PROJECT_ID", "local-llm")
langfuse_host = os.environ.get("LANGFUSE_HOST", "http://localhost:3000")

client = openai.OpenAI(base_url=f"http://{ollama_host}/v1", api_key="ollama")
langfuse = get_client()

with langfuse.start_as_current_observation(name="sanctum-local-llm", as_type="span") as span:
    response = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": "Answer in one sentence."},
            {"role": "user", "content": "What does an LLM observability tool record about a request?"},
        ],
    )
    trace_id = span.trace_id

print(response.choices[0].message.content.strip())

langfuse.flush()

url = f"{langfuse_host}/project/{project_id}/traces/{trace_id}"
print(f"\ntrace: {url}", file=sys.stderr)
