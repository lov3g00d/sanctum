# app/

Two sample services that stand in for the Nimbus workloads. They are minimal but
runnable, and they exist mainly to give `docker/`, `kubernetes/`, and
`monitoring/` something concrete with real health, readiness, and metrics
endpoints to target.

| Service | Stack | Port | Compute plane |
|---------|-------|:----:|---------------|
| `orders-api` | Node.js 22 / Express | 3000 | EKS (always-on core API) |
| `ledger-py` | Python 3.12 / FastAPI | 8000 | Lambda + API Gateway (also runs on EKS) |

`ledger-py` is written so the same ASGI app runs behind uvicorn on Kubernetes and
behind API Gateway on Lambda through a Mangum handler (`app.main.handler`). That
mirrors the "right tool for the job" compute split in `docs/00-scenario.md`.

## Shared contract

Both services expose the same operational endpoints so one probe, one scrape
config, and one dashboard shape cover both:

| Endpoint | Meaning |
|----------|---------|
| `GET /healthz` | Liveness. Always 200 while the process is up. |
| `GET /readyz` | Readiness. 200 when the dependency check passes, 503 otherwise. Drives rolling-deploy gating and load-balancer draining. |
| `GET /metrics` | Prometheus exposition: default process/runtime metrics plus `http_requests_total` and `http_request_duration_seconds`. |

Both read `PORT` from the environment, log structured JSON to stdout, and fail
readiness before exiting on `SIGTERM` so traffic drains during a rolling deploy.
`scripts/health-check.sh` probes the `/healthz` and `/readyz` pair from outside
the cluster.

## orders-api (Node.js/Express)

```sh
cd orders-api
npm install
npm start            # listens on PORT (default 3000)
npm test             # node --test
```

REST resource: `GET /v1/orders`, `POST /v1/orders` (`{ "sku": "WIDGET-1",
"quantity": 3 }`), in-memory.

## ledger-py (Python/FastAPI)

```sh
cd ledger-py
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python -m app.main   # listens on PORT (default 8000)

pip install -r requirements-dev.txt   # adds pytest + httpx for the tests
pytest
```

REST resource: `GET /v1/entries`, `POST /v1/entries` (`{ "account": "acct-1",
"amount_cents": 500 }`), in-memory. The Lambda handler is `app.main.handler`.
