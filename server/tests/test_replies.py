"""Text reply parsing and the Chert webhook."""

import pytest

from rules import extract_inbound, parse_reply


@pytest.mark.parametrize(("text", "expected"), [
    ("1", ("safe", None)),
    (" 1 ", ("safe", None)),
    ("1.", ("safe", None)),
    ("2", ("help", None)),
    ("2!", ("help", None)),
    ("stuck under a beam", ("help", "stuck under a beam")),
    ("12", ("help", "12")),
    ("", ("help", None)),
])
def test_parse_reply(text, expected):
    assert parse_reply(text) == expected


def test_extract_inbound_flat_and_nested():
    assert extract_inbound({"from": "+15550001", "text": "1"}) == ("+15550001", "1")
    assert extract_inbound({"data": {"sender": "+15550001", "body": "2"}}) == ("+15550001", "2")
    assert extract_inbound({"nothing": "here"}) == (None, None)


def statuses(client) -> dict[str, str]:
    return {w["name"]: w["status"] for w in client.get("/state").json()["workers"]}


def test_webhook_replies_update_checkins(client, join):
    join("Ana")  # +15550000001
    join("Ben")  # +15550000002
    join("Cy")   # +15550000003
    client.post("/rescue/start", json={"reason": "test"})

    # Different phone formats still match the worker.
    client.post("/chert/webhook", json={"from": "+1 (555) 000-0001", "text": "1"})
    client.post("/chert/webhook", json={"from": "5550000002", "text": "2"})
    client.post("/chert/webhook", json={"from": "+15550000003", "text": "trapped, floor 2"})

    assert statuses(client) == {"Ana": "safe", "Ben": "help", "Cy": "help"}


def test_webhook_from_unknown_number_is_ignored(client, join):
    join("Ana")
    client.post("/rescue/start", json={"reason": "test"})
    reply = client.post("/chert/webhook", json={"from": "+19999999999", "text": "1"})
    assert reply.json() == {"ok": True}
    assert statuses(client) == {"Ana": "none"}


def test_webhook_with_bad_body_does_not_crash(client):
    assert client.post("/chert/webhook", content=b"not json").json() == {"ok": True}
