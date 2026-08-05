from fastapi.testclient import TestClient

from app.main import app, set_dependency_ready

client = TestClient(app)


def test_healthz():
    assert client.get("/healthz").status_code == 200


def test_readyz_reflects_dependency():
    set_dependency_ready(True)
    assert client.get("/readyz").status_code == 200
    set_dependency_ready(False)
    assert client.get("/readyz").status_code == 503
    set_dependency_ready(True)


def test_metrics_text():
    res = client.get("/metrics")
    assert res.status_code == 200
    assert "http_requests_total" in res.text


def test_entries_roundtrip():
    created = client.post("/v1/entries", json={"account": "acct-1", "amount_cents": 500})
    assert created.status_code == 201
    entry_id = created.json()["id"]
    listed = client.get("/v1/entries").json()["entries"]
    assert any(e["id"] == entry_id for e in listed)


def test_invalid_entry_rejected():
    assert client.post("/v1/entries", json={"amount_cents": 5}).status_code == 422
