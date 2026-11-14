"""Small pure rules: collapse trigger, text reply parsing, webhook field lookup."""

from typing import Any


def is_collapse(phones_with_shock: int, phones_needed: int) -> bool:
    """True when enough different phones felt a shock inside the time window."""
    return phones_with_shock >= phones_needed


def parse_reply(text: str) -> tuple[str, str | None]:
    """Turn a worker's text reply into (status, note).

    "1" -> safe. "2" -> help. Anything else -> help, and the text is kept as a note.
    """
    cleaned = text.strip().strip(".!")
    if cleaned == "1":
        return "safe", None
    if cleaned == "2":
        return "help", None
    return "help", (text.strip() or None)


# TODO(Chert): the real webhook field names are unknown. These are guesses that cover
# the common shapes. Replace with the exact fields from docs.trychert.com.
_SENDER_KEYS = ("from", "from_number", "sender", "phone", "phone_number", "handle")
_TEXT_KEYS = ("text", "body", "content", "message")


def extract_inbound(payload: dict[str, Any]) -> tuple[str | None, str | None]:
    """Find (sender phone, message text) in a webhook body. Looks one level deep too."""
    layers = [payload] + [v for v in payload.values() if isinstance(v, dict)]
    sender = next((str(layer[k]) for layer in layers for k in _SENDER_KEYS
                   if isinstance(layer.get(k), (str, int))), None)
    text = next((layer[k] for layer in layers for k in _TEXT_KEYS
                 if isinstance(layer.get(k), str)), None)
    return sender, text
