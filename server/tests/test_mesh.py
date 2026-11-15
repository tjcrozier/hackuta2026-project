"""Mesh upload: dedupe, and applying help / safe / ping / text / rescue."""

import config


def message(msg_id: str, origin: str, kind: str, body: str = "", created_at: float = 1_763_059_990,
            **extra) -> dict:
    return {"msg_id": msg_id, "origin_worker_id": origin, "type": kind, "body": body,
            "zone": "B", "floor": 3, "battery": 61, "created_at": created_at, "ttl": 3,
            "path": [origin, "w9"], **extra}


def upload(client, *messages: dict) -> dict:
    return client.post("/mesh/upload", json={"messages": list(messages)}).json()


def worker(client, name: str) -> dict:
    return next(w for w in client.get("/state").json()["workers"] if w["name"] == name)


def test_same_message_from_two_phones_counts_once(client, join):
    a = join("Ana")
    client.post("/rescue/start", json={"reason": "test"})
    help_message = message("m1", a, "help", "I need help")

    assert upload(client, help_message) == {"accepted": 1, "duplicates": 0}
    # A second phone carried the same message: it must not be applied again.
    assert upload(client, help_message, message("m2", a, "text", "under the stairs")) == {
        "accepted": 1, "duplicates": 1}
    assert upload(client, help_message) == {"accepted": 0, "duplicates": 1}

    mesh_texts = [m["body"] for m in client.get("/state").json()["messages"]
                  if m["direction"] == "in"]
    assert sorted(mesh_texts) == ["I need help", "under the stairs"]


def test_help_becomes_a_checkin_and_a_ping_via_mesh(client, join):
    a = join("Ana")
    client.post("/rescue/start", json={"reason": "test"})
    upload(client, message("m1", a, "help", "I need help"))
    ana = worker(client, "Ana")
    assert (ana["status"], ana["source"], ana["zone"], ana["floor"], ana["battery"]) == (
        "help", "mesh", "B", 3, 61)
    assert ana["moving"] is False


def test_later_safe_wins_even_if_uploaded_in_the_wrong_order(client, join):
    a = join("Ana")
    client.post("/rescue/start", json={"reason": "test"})
    upload(client,
           message("m2", a, "safe", "I'm safe", created_at=1_763_059_995),
           message("m1", a, "help", "I need help", created_at=1_763_059_990))
    assert worker(client, "Ana")["status"] == "safe"


def test_mesh_ping_updates_position_but_not_status(client, join):
    a = join("Ana")
    upload(client, message("m1", a, "ping", zone="C", floor=2))
    ana = worker(client, "Ana")
    assert (ana["zone"], ana["floor"], ana["source"], ana["status"]) == ("C", 2, "mesh", "none")


def test_newer_internet_ping_is_not_replaced_by_an_older_mesh_message(client, join):
    a = join("Ana")
    client.post("/ping", json={"worker_id": a, "zone": "A", "floor": 1, "battery": 90,
                               "moving": True, "source": "internet"})
    upload(client, message("m1", a, "ping", zone="C", floor=2, created_at=1_763_059_000))
    ana = worker(client, "Ana")
    assert (ana["zone"], ana["floor"], ana["source"]) == ("A", 1, "internet")


def test_offline_rescue_message_starts_rescue_once(client, join):
    a, b = join("Ana"), join("Ben")
    upload(client, message("r1", a, "rescue", "impact on 3 phones (offline)"),
           message("r2", b, "rescue", "impact on 3 phones (offline)"))
    state = client.get("/state").json()
    assert state["rescue"] == {"active": True, "reason": "impact on 3 phones (offline)",
                               "started_at": 1_763_060_000}
    emergency = [m for m in state["messages"] if "CYCL0PS EMERGENCY" in m["body"]]
    assert len(emergency) == 2  # one text per worker, not per rescue message


def test_unknown_worker_and_unknown_type_are_accepted_but_ignored(client, join):
    a = join("Ana")
    assert upload(client, message("m1", "nobody", "help"),
                  message("m2", a, "ni_token", "abc")) == {"accepted": 2, "duplicates": 0}
    assert worker(client, "Ana")["status"] == "none"


def test_mesh_can_be_turned_off(client, monkeypatch):
    monkeypatch.setattr(config, "FEATURE_MESH", False)
    assert client.post("/mesh/upload", json={"messages": []}).status_code == 403
