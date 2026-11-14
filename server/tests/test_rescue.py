"""Collapse trigger, rescue start/stop, and check-in counts."""

from collections import Counter

import db


def shock(client, worker_id: str) -> bool:
    body = {"worker_id": worker_id, "type": "shock"}
    return client.post("/event", json=body).json()["rescue_active"]


def status_counts(client) -> Counter:
    return Counter(w["status"] for w in client.get("/state").json()["workers"])


def test_two_phones_do_not_start_rescue(client, join):
    a, b, _ = join("Ana"), join("Ben"), join("Cy")
    assert shock(client, a) is False
    assert shock(client, b) is False
    assert client.get("/state").json()["rescue"]["active"] is False


def test_three_phones_start_rescue(client, join, clock):
    a, b, c = join("Ana"), join("Ben"), join("Cy")
    shock(client, a)
    clock.tick(2)
    shock(client, b)
    clock.tick(2)
    assert shock(client, c) is True
    rescue = client.get("/state").json()["rescue"]
    assert rescue["active"] is True
    assert rescue["reason"] == "impact on 3 phones"


def test_three_phones_over_six_seconds_do_not_start_rescue(client, join, clock):
    a, b, c = join("Ana"), join("Ben"), join("Cy")
    shock(client, a)
    clock.tick(3)
    shock(client, b)
    clock.tick(3)  # 6 s after the first shock: outside the 5 s window
    assert shock(client, c) is False


def test_one_phone_shaking_three_times_does_not_start_rescue(client, join):
    a = join("Ana")
    join("Ben")
    join("Cy")
    assert [shock(client, a) for _ in range(3)] == [False, False, False]


def test_rescue_start_texts_every_worker_and_resets_checkins(client, join):
    join("Ana")
    join("Ben")
    rescue = client.post("/rescue/start", json={"reason": "supervisor button"}).json()
    assert rescue["active"] is True
    assert rescue["reason"] == "supervisor button"

    state = client.get("/state").json()
    assert status_counts(client) == {"none": 2}
    bodies = [m["body"] for m in state["messages"]]
    assert len(bodies) == 2
    assert "BLACK BOX EMERGENCY. Ana, are you OK? Reply 1 if safe, 2 if you need help." in bodies


def test_starting_twice_keeps_one_rescue(client, join):
    join("Ana")
    first = client.post("/rescue/start", json={"reason": "one"}).json()
    second = client.post("/rescue/start", json={"reason": "two"}).json()
    assert first["id"] == second["id"]
    assert len(client.get("/state").json()["messages"]) == 1


def test_checkin_counts(client, join):
    a, b, _, _ = join("Ana"), join("Ben"), join("Cy"), join("Di")
    client.post("/rescue/start", json={"reason": "test"})
    client.post("/checkin", json={"worker_id": a, "status": "safe"})
    client.post("/checkin", json={"worker_id": b, "status": "help", "note": "leg"})
    assert status_counts(client) == {"safe": 1, "help": 1, "none": 2}

    # Changing an answer replaces the old one.
    client.post("/checkin", json={"worker_id": b, "status": "safe"})
    assert status_counts(client) == {"safe": 2, "none": 2}


def test_rescue_stop(client, join):
    join("Ana")
    client.post("/rescue/start", json={"reason": "test"})
    stopped = client.post("/rescue/stop").json()
    assert stopped["active"] is False
    assert stopped["ended_at"] is not None
    assert client.get("/state").json()["rescue"]["active"] is False


def test_ping_reports_rescue(client, join):
    a = join("Ana")
    ping = {"worker_id": a, "zone": "B", "floor": 3, "battery": 64, "moving": True,
            "source": "internet"}
    assert client.post("/ping", json=ping).json()["rescue_active"] is False
    client.post("/rescue/start", json={"reason": "test"})
    reply = client.post("/ping", json=ping).json()
    assert reply["rescue_active"] is True
    assert reply["rescue_id"] == db.active_rescue()["id"]


def test_fall_alert_texts_supervisor(client, join):
    a = join("Ana")
    client.post("/ping", json={"worker_id": a, "zone": "B", "floor": 3, "battery": 64,
                               "moving": False, "source": "internet"})
    client.post("/event", json={"worker_id": a, "type": "fall_alert"})
    bodies = [m["body"] for m in client.get("/state").json()["messages"]]
    assert bodies == ["Possible fall: Ana, Floor 3, Zone B."]


def test_no_move_texts_supervisor(client, join):
    a = join("Ana")
    client.post("/ping", json={"worker_id": a, "zone": "C", "floor": 2, "battery": 64,
                               "moving": False, "source": "internet"})
    client.post("/event", json={"worker_id": a, "type": "no_move"})
    bodies = [m["body"] for m in client.get("/state").json()["messages"]]
    assert bodies == ["No movement and no answer: Ana, Floor 2, Zone C."]


def test_fall_and_fall_ok_send_no_text(client, join):
    a = join("Ana")
    client.post("/event", json={"worker_id": a, "type": "fall"})
    client.post("/event", json={"worker_id": a, "type": "fall_ok"})
    assert client.get("/state").json()["messages"] == []
