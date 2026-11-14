"""Sending texts. FakeSender is the fallback that always works for the demo."""

import logging
from typing import Protocol

import httpx

import config
import db

log = logging.getLogger("blackbox.senders")


class MessageSender(Protocol):
    async def send(self, to: str, body: str) -> None: ...


class FakeSender:
    """Does not send anything. Logs the text and saves it so the dashboard can show it."""

    async def send(self, to: str, body: str) -> None:
        log.info("FAKE TEXT to %s: %s", to, body)
        db.add_message("out", to, body, "fake")


class ChertSender:
    """Sends a real iMessage/SMS through Chert."""

    def __init__(self, api_key: str, base_url: str) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")

    async def send(self, to: str, body: str) -> None:
        # TODO(Chert): the endpoint path, auth header and body fields below are GUESSES.
        # Paste the real ones from docs.trychert.com or the Chert booth.
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.post(
                    f"{self.base_url}/messages",
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    json={"to": to, "text": body},
                )
                response.raise_for_status()
            db.add_message("out", to, body, "chert")
        except httpx.HTTPError as error:
            # Never let a failed text break Rescue Mode. Fall back to the fake sender.
            log.warning("Chert send failed (%s). Using FakeSender for this text.", error)
            await FakeSender().send(to, body)


def get_sender() -> MessageSender:
    """ChertSender when a key and base URL are set, otherwise FakeSender."""
    if config.CHERT_API_KEY and config.CHERT_BASE_URL:
        return ChertSender(config.CHERT_API_KEY, config.CHERT_BASE_URL)
    return FakeSender()
