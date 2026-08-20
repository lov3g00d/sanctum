import os
import socket

import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)


def db_message():
    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=3,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT body FROM messages ORDER BY id LIMIT 1")
            row = cur.fetchone()
            return row[0] if row else None
    finally:
        conn.close()


@app.get("/")
def index():
    try:
        return jsonify(
            host=socket.gethostname(),
            version=os.environ.get("APP_VERSION"),
            db_message=db_message(),
        )
    except Exception as exc:  # noqa: BLE001 - surface DB errors to the caller
        return jsonify(host=socket.gethostname(), error=str(exc)), 500


@app.get("/healthz")
def healthz():
    return "ok\n", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("APP_PORT", "8080")))
