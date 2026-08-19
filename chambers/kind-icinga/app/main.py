import os
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

state = {
    "healthy": True,
    "latency_ms": 0,
}


@app.get("/")
def index():
    return jsonify(app="webapp", healthy=state["healthy"], latency_ms=state["latency_ms"])


@app.get("/healthz")
def healthz():
    if state["latency_ms"] > 0:
        time.sleep(state["latency_ms"] / 1000.0)
    if state["healthy"]:
        return "ok\n", 200
    return "unhealthy\n", 500


@app.post("/config")
def config():
    body = request.get_json(force=True, silent=True) or {}
    if "healthy" in body:
        state["healthy"] = bool(body["healthy"])
    if "latency_ms" in body:
        state["latency_ms"] = int(body["latency_ms"])
    return jsonify(state)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
