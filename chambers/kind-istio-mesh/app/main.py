import os
import random
import socket
import time

from flask import Flask, jsonify, request

app = Flask(__name__)
VERSION = os.environ.get("VERSION", "v1")

# Runtime knobs so the mesh's resilience features have something to act on:
# latency feeds the timeout demo, error_rate feeds the retry demo.
cfg = {
    "error_rate": float(os.environ.get("ERROR_RATE", "0")),
    "latency_ms": int(os.environ.get("LATENCY_MS", "0")),
}


@app.get("/")
def index():
    time.sleep(cfg["latency_ms"] / 1000.0)
    body = {"app": "web", "version": VERSION, "pod": socket.gethostname()}
    if random.random() < cfg["error_rate"]:
        body["error"] = True
        return jsonify(body), 503
    return jsonify(body)


@app.route("/config", methods=["GET", "POST"])
def config():
    if request.method == "POST":
        data = request.get_json(silent=True) or request.args
        if "error_rate" in data:
            cfg["error_rate"] = float(data["error_rate"])
        if "latency_ms" in data:
            cfg["latency_ms"] = int(data["latency_ms"])
    return jsonify(cfg)


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
