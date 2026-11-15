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


# ---- Athena Live: questions about a camera picture ----

JPEG = "/9j/4AAQSkZJRgABAQAAAQABAAD" + "A" * 200  # starts like a real JPEG


def look(client, image=JPEG, question="Can I drink it?", previous=None):
    body = {"image": image, "question": question}
    if previous:
        body["previous_question"] = previous
    return client.post("/athena/look", json=body)


def test_look_is_offline_without_a_key(client):
    assert look(client).json() == {"reply": athena.LOOK_OFFLINE_REPLY, "source": "offline"}


def test_look_sends_the_picture_and_question_to_the_vision_model(client, monkeypatch):
    sent = []

    async def _ask(messages, model=None):
        sent.append((messages, model))
        return "No. That is bleach. Do not drink it."

    monkeypatch.setattr(config, "GROQ_API_KEY", "test-key")
    monkeypatch.setattr(athena, "ask_groq", _ask)
    reply = look(client, previous="What is this?").json()
    assert reply == {"reply": "No. That is bleach. Do not drink it.", "source": "groq"}
    messages, model = sent[0]
    assert model == config.GROQ_VISION_MODEL
    text, picture = messages[1]["content"]
    assert "Can I drink it?" in text["text"] and "What is this?" in text["text"]
    assert picture["image_url"]["url"] == "data:image/jpeg;base64," + JPEG


def test_look_refuses_something_that_is_not_a_picture(client):
    assert look(client, image="aGVsbG8gd29ybGQ" + "A" * 200).status_code == 400


def test_look_is_offline_when_groq_fails(client, monkeypatch):
    async def broken(messages, model=None):
        raise httpx.ConnectError("down")

    monkeypatch.setattr(config, "GROQ_API_KEY", "test-key")
    monkeypatch.setattr(athena, "ask_groq", broken)
    assert look(client).json()["source"] == "offline"


def test_thinking_tags_are_removed(monkeypatch):
    import asyncio

    class FakeResponse:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": "<think>hmm</think> It is bleach."}}]}

    class FakeClient:
        def __init__(self, **_):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            pass

        async def post(self, *_, **__):
            return FakeResponse()

    monkeypatch.setattr(athena.httpx, "AsyncClient", FakeClient)
    assert asyncio.run(athena.ask_groq([], "qwen/qwen3.8-27b")) == "It is bleach."
