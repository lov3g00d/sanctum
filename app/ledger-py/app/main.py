from __future__ import annotations

import json
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response, status
from fastapi.responses import JSONResponse
from mangum import Mangum
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel, Field

registry = CollectorRegistry()

http_requests_total = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "route", "status_code"],
    registry=registry,
)
http_request_duration_seconds = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "route", "status_code"],
    registry=registry,
)


def _log(level: str, message: str, **extra: object) -> None:
    record = {"level": level, "service": "nimbus-ledger", "message": message, **extra}
    sys.stdout.write(json.dumps(record) + "\n")
    sys.stdout.flush()


# Stubs a database dependency. A real deploy would ping RDS here.
_dependency_ready = True


def set_dependency_ready(value: bool) -> None:
    global _dependency_ready
    _dependency_ready = value


async def check_dependency() -> bool:
    return _dependency_ready


@asynccontextmanager
async def lifespan(_app: FastAPI):
    _log("info", "startup")
    yield
    # Fail readiness before the worker stops so the balancer drains first.
    set_dependency_ready(False)
    _log("info", "shutdown")


app = FastAPI(title="nimbus-ledger", lifespan=lifespan)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    matched = request.scope.get("route")
    # Constant label for unmatched paths keeps 404 floods from exploding cardinality.
    route = getattr(matched, "path", "unmatched")
    labels = {
        "method": request.method,
        "route": route,
        "status_code": str(response.status_code),
    }
    http_requests_total.labels(**labels).inc()
    http_request_duration_seconds.labels(**labels).observe(time.perf_counter() - start)
    return response


class EntryIn(BaseModel):
    account: str = Field(min_length=1)
    amount_cents: int
    currency: str = Field(default="EUR", min_length=3, max_length=3)


class Entry(EntryIn):
    id: str


_entries: dict[str, Entry] = {}


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz() -> Response:
    if await check_dependency():
        return JSONResponse({"status": "ready"})
    return JSONResponse({"status": "not_ready"}, status_code=status.HTTP_503_SERVICE_UNAVAILABLE)


@app.get("/metrics")
async def metrics() -> Response:
    return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)


@app.get("/v1/entries")
async def list_entries() -> dict[str, list[Entry]]:
    return {"entries": list(_entries.values())}


@app.post("/v1/entries", status_code=status.HTTP_201_CREATED)
async def create_entry(payload: EntryIn) -> Entry:
    entry = Entry(id=str(uuid.uuid4()), **payload.model_dump())
    _entries[entry.id] = entry
    return entry


# Lambda entrypoint: API Gateway -> Mangum -> the same ASGI app that runs on EKS.
handler = Mangum(app)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8000")),
        access_log=False,
    )
