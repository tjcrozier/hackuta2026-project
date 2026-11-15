"""Athena chat: offline fallback, what each role may see, Groq errors."""

import httpx

import athena
import config


def ping(client, worker_id, zone, floor):
    client.post("/ping", json={"worker_id": worker_id, "zone": zone, "floor": floor,
                               "battery": 70, "moving": True, "source": "internet"})


def ask(client, role, text="Who needs help?", worker_id=None):
    body = {"role": role, "messages": [{"role": "user", "text": text}]}
    if worker_id:
        body["worker_id"] = worker_id
    return client.post("/athena/chat", json=body)


def fake_groq(monkeypatch, answer="OK."):
    """Replace the Groq call; returns the list of message lists it was given."""
    calls = []

    async def _ask(messages):
        calls.append(messages)
        return answer

    monkeypatch.setattr(config, "GROQ_API_KEY", "test-key")
    monkeypatch.setattr(athena, "ask_groq", _ask)
    return calls


def test_offline_without_a_key(client):
    reply = ask(client, "supervisor").json()
    assert reply == {"reply": athena.OFFLINE_REPLY, "source": "offline"}


def test_offline_when_feature_is_off(client, monkeypatch):
    fake_groq(monkeypatch)
    monkeypatch.setattr(config, "FEATURE_ATHENA", False)
    assert ask(client, "supervisor").json()["source"] == "offline"


def test_supervisor_sees_every_worker_and_hazard(client, join, monkeypatch):
    calls = fake_groq(monkeypatch, "Ben needs help.")
    ana, ben = join("Ana"), join("Ben")
    ping(client, ana, "A", 1)
    ping(client, ben, "C", 3)
    client.post("/rescue/start", json={"reason": "test"})
    client.post("/checkin", json={"worker_id": ben, "status": "help"})

    assert ask(client, "supervisor").json() == {"reply": "Ben needs help.", "source": "groq"}
    data = calls[0][1]["content"]
    assert "Rescue Mode is ON." in data
    assert "Ana: Floor 1, Zone A" in data and "no answer yet" in data
    assert "Ben: Floor 3, Zone C (nearest stairs: Stair 2, south side), NEEDS HELP" in data
    assert calls[0][-1] == {"role": "user", "content": "Who needs help?"}


def test_worker_sees_only_themselves(client, join, monkeypatch):
    calls = fake_groq(monkeypatch)
    ana, ben = join("Ana"), join("Ben")
    ping(client, ana, "B", 2)
    ping(client, ben, "C", 2)

    assert ask(client, "worker", worker_id=ana).status_code == 200
    data = calls[0][1]["content"]
    assert "You are talking to Ana, on Floor 2, Zone B" in data
    assert "Ben" not in data


def test_worker_must_be_known(client):
    assert ask(client, "worker").status_code == 404
    assert ask(client, "worker", worker_id="nobody").status_code == 404


def test_groq_error_gives_offline_reply(client, monkeypatch):
    monkeypatch.setattr(config, "GROQ_API_KEY", "test-key")

    async def broken(_messages):
        raise httpx.ConnectError("network down")

    monkeypatch.setattr(athena, "ask_groq", broken)
    assert ask(client, "rescuer").json()["source"] == "offline"


def test_only_the_latest_turns_are_sent(client, monkeypatch):
    calls = fake_groq(monkeypatch)
    turns = [{"role": "user" if i % 2 == 0 else "assistant", "text": f"m{i}"} for i in range(21)]
    client.post("/athena/chat", json={"role": "supervisor", "messages": turns})
    sent = calls[0][2:]  # after the two system messages
    assert len(sent) == athena.MAX_TURNS
    assert sent[-1]["content"] == "m20"


def test_gpt_oss_models_think_briefly(monkeypatch):
    monkeypatch.setattr(config, "GROQ_MODEL", "openai/gpt-oss-120b")
    assert athena.request_body([])["reasoning_effort"] == "low"
    monkeypatch.setattr(config, "GROQ_MODEL", "qwen/qwen3.8-27b")
    assert "reasoning_effort" not in athena.request_body([])
