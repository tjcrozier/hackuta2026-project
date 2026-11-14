import pytest
from fastapi.testclient import TestClient

import config
import db
from main import app


class Clock:
    """A fake clock so tests can move time forward."""

    def __init__(self) -> None:
        self.t = 1_763_060_000.0

    def __call__(self) -> float:
        return self.t

    def tick(self, seconds: float) -> None:
        self.t += seconds


@pytest.fixture
def clock(monkeypatch: pytest.MonkeyPatch) -> Clock:
    fake = Clock()
    monkeypatch.setattr(db, "now", fake)
    return fake


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch, clock: Clock, tmp_path):
    """A test client with an empty in-memory database and the FakeSender."""
    monkeypatch.setenv("BB_DB_PATH", ":memory:")
    monkeypatch.setattr(config, "SCANS_DIR", str(tmp_path / "scans"))
    monkeypatch.setattr(config, "SUPERVISOR_PHONE", "+10000000000")
    monkeypatch.setattr(config, "FEATURE_SCAN_COMPARE", True)
    monkeypatch.setattr(config, "CHERT_API_KEY", "")
    monkeypatch.setattr(config, "DEMO_MODE", True)
    monkeypatch.setattr(config, "DEMO_WORKERS", True)  # tests ignore server/.env
    monkeypatch.setattr(config, "SITE_CODE", "ARL-0412")
    monkeypatch.setattr(config, "COLLAPSE_PHONES", 3)
    monkeypatch.setattr(config, "COLLAPSE_WINDOW_SEC", 5.0)
    with TestClient(app) as test_client:
        db.clear_all()  # drop the demo seed; each test starts empty
        yield test_client


@pytest.fixture
def join(client: TestClient):
    """join("Ana") -> worker id. Each worker gets a different phone number."""
    count = 0

    def _join(name: str) -> str:
        nonlocal count
        count += 1
        body = {"name": name, "phone": f"+1555000{count:04d}", "site_code": "ARL-0412"}
        return client.post("/workers/join", json=body).json()["worker_id"]

    return _join
