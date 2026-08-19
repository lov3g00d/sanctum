import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)
VERSION = os.environ.get("VERSION", "v1")


@app.get("/")
def index():
    return jsonify(app="web", version=VERSION, pod=socket.gethostname())


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
