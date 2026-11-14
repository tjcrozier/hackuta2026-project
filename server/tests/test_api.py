"""Join, pings, snapshot shape, live socket, demo reset."""

import config


def test_join_ping_and_state(client, join):
    a = join("Ana")
    client.post("/ping", json={"worker_id": a, "zone": "B", "floor": 3, "battery": 64,
                               "moving": True, "source": "internet"})
    state = client.get("/state").json()
    assert set(state) == {"site", "rescue", "workers", "hazards", "scans", "messages"}
    assert state["site"] == {"name": config.SITE_NAME, "code": "ARL-0412"}
    worker = state["workers"][0]
    assert worker == {"id": a, "name": "Ana", "zone": "B", "floor": 3, "battery": 64,
                      "last_ping": 1_763_060_000, "moving": True, "source": "internet",
                      "status": "none", "phone_lost": False}


def test_join_with_wrong_site_code_fails(client):
    body = {"name": "Ana", "phone": "+15550000001", "site_code": "NOPE"}
    assert client.post("/workers/join", json=body).status_code == 400


def test_joining_again_with_same_phone_keeps_the_same_worker(client):
    body = {"name": "Ana", "phone": "+15550000001", "site_code": "arl-0412"}
    first = client.post("/workers/join", json=body).json()["worker_id"]
    second = client.post("/workers/join", json=body).json()["worker_id"]
    assert first == second
    assert len(client.get("/state").json()["workers"]) == 1


def test_ping_from_unknown_worker_is_404(client):
    body = {"worker_id": "nobody", "zone": "A", "floor": 1, "battery": 50, "moving": True,
            "source": "internet"}
    assert client.post("/ping", json=body).status_code == 404


def test_phone_lost_after_no_pings(client, join, clock):
    a = join("Ana")
    client.post("/ping", json={"worker_id": a, "zone": "A", "floor": 1, "battery": 50,
                               "moving": True, "source": "internet"})
    clock.tick(config.PHONE_LOST_SEC + 1)
    assert client.get("/state").json()["workers"][0]["phone_lost"] is True


def test_help_outside_rescue_texts_supervisor(client, join):
    a = join("Ana")
    client.post("/checkin", json={"worker_id": a, "status": "help"})
    state = client.get("/state").json()
    assert state["workers"][0]["status"] == "help"
    assert state["messages"][0]["body"] == "Ana needs help. Floor ?, Zone ?."


def test_live_socket_pushes_snapshot_on_change(client, join):
    with client.websocket_connect("/live") as socket:
        assert socket.receive_json()["workers"] == []
        join("Ana")
        assert [w["name"] for w in socket.receive_json()["workers"]] == ["Ana"]


def test_demo_reset_seeds_14_workers_and_3_scans(client, monkeypatch):
    assert client.post("/demo/reset").json() == {"ok": True}
    state = client.get("/state").json()
    assert len(state["workers"]) == 14
    assert sorted({w["floor"] for w in state["workers"]}) == [1, 2, 3]
    assert sorted(state["scans"]) == ["1", "2", "3"]

    monkeypatch.setattr(config, "DEMO_MODE", False)
    assert client.post("/demo/reset").status_code == 403


def test_demo_workers_keep_pinging_but_real_workers_do_not(client, join, clock):
    import demo

    client.post("/demo/reset")
    real = join("Real Person")
    client.post("/ping", json={"worker_id": real, "zone": "A", "floor": 1, "battery": 50,
                               "moving": True, "source": "internet"})
    clock.tick(config.PHONE_LOST_SEC + 1)
    assert demo.refresh_pings() == 14
    workers = {w["name"]: w for w in client.get("/state").json()["workers"]}
    assert workers["Sajid H."]["phone_lost"] is False
    assert (workers["Sajid H."]["floor"], workers["Sajid H."]["zone"]) == (3, "B")
    assert workers["Real Person"]["phone_lost"] is True


def test_end_shift_hides_worker_until_next_ping(client, join):
    a, b = join("Ana"), join("Ben")
    ping = {"worker_id": a, "zone": "A", "floor": 1, "battery": 80, "moving": True,
            "source": "internet"}
    client.post("/ping", json=ping)
    assert client.post(f"/workers/{a}/end_shift").json() == {"ok": True}
    assert [w["id"] for w in client.get("/state").json()["workers"]] == [b]
    client.post("/ping", json=ping)  # starts the shift again
    assert {w["id"] for w in client.get("/state").json()["workers"]} == {a, b}
    assert client.post("/workers/nobody/end_shift").status_code == 404


def test_demo_reset_without_fake_workers(client, monkeypatch):
    monkeypatch.setattr(config, "DEMO_WORKERS", False)
    client.post("/demo/reset")
    state = client.get("/state").json()
    assert state["workers"] == []
    assert sorted(state["scans"]) == ["1", "2", "3"]  # demo floors are still there
