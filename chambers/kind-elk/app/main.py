import os
import random
import threading
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

state = {"healthy": True}

PATHS = ["/", "/api/users", "/api/orders", "/api/search", "/healthz"]
METHODS = ["GET", "POST", "PUT"]


def emitter():
    """Emit one semi-structured text log line per second to stdout.

    Format: LEVEL STATUS METHOD PATH LATENCYms MESSAGE
    This is deliberately NOT JSON so the Logstash grok filter has to parse it.
    """
    while True:
        if state["healthy"]:
            level, status, msg = "INFO", 200, "request served"
            latency = random.randint(2, 40)
        elif random.random() < 0.7:
            level, status, msg = "ERROR", 500, "internal server error"
            latency = random.randint(80, 500)
        else:
            level, status, msg = "WARN", 200, "elevated latency"
            latency = random.randint(60, 200)
        line = f"{level} {status} {random.choice(METHODS)} {random.choice(PATHS)} {latency}ms {msg}"
        print(line, flush=True)
        time.sleep(1)


@app.get("/")
def index():
    return jsonify(app="loggen", healthy=state["healthy"])


@app.post("/config")
def config():
    body = request.get_json(force=True, silent=True) or {}
    if "healthy" in body:
        state["healthy"] = bool(body["healthy"])
    return jsonify(state)


if __name__ == "__main__":
    threading.Thread(target=emitter, daemon=True).start()
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
