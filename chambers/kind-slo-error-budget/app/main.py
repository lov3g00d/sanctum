import os
import random
import time

from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = Flask(__name__)

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "path", "status"])
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds",
    ["path"],
    buckets=(0.05, 0.1, 0.2, 0.5, 1.0, 2.5, 5.0),
)

# Runtime-tunable behaviour: the knobs the break/heal demo flips to burn the
# error budget (inject 5xx) or add latency.
cfg = {
    "error_rate": float(os.environ.get("ERROR_RATE", "0")),
    "latency_ms": int(os.environ.get("LATENCY_MS", "0")),
}


@app.get("/")
def index():
    start = time.perf_counter()
    time.sleep(cfg["latency_ms"] / 1000.0 + random.uniform(0, 0.02))
    status = 500 if random.random() < cfg["error_rate"] else 200
    LATENCY.labels("/").observe(time.perf_counter() - start)
    REQUESTS.labels(request.method, "/", str(status)).inc()
    return jsonify(ok=(status == 200)), status


@app.route("/config", methods=["GET", "POST"])
def config():
    if request.method == "POST":
        data = request.get_json(silent=True) or request.args
        if "error_rate" in data:
            cfg["error_rate"] = float(data["error_rate"])
        if "latency_ms" in data:
            cfg["latency_ms"] = int(data["latency_ms"])
    return jsonify(cfg)


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
