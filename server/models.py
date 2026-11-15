"""Request bodies for the REST API (see BUILD_PLAN.md, "REST API")."""

from typing import Literal

from pydantic import BaseModel, Field


class JoinBody(BaseModel):
    name: str = Field(min_length=1)
    phone: str = Field(min_length=1)
    site_code: str


class PingBody(BaseModel):
    worker_id: str
    zone: str | None = None
    floor: int | None = None
    battery: int | None = None
    lat: float | None = None
    lng: float | None = None
    moving: bool = True
    source: Literal["internet", "mesh"] = "internet"


class EventBody(BaseModel):
    worker_id: str
    type: Literal["shock", "fall", "fall_ok", "fall_alert", "no_move"]


class RescueStartBody(BaseModel):
    reason: str = "supervisor button"


class CheckinBody(BaseModel):
    worker_id: str
    status: Literal["none", "safe", "help"]
    note: str | None = None


class HazardBody(BaseModel):
    status: Literal["open", "fixed", "false_alarm"]


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    text: str = Field(min_length=1, max_length=2000)


class AthenaBody(BaseModel):
    """The chat so far. worker_id is needed for role "worker" (Athena only sees that worker)."""

    role: Literal["worker", "supervisor", "rescuer"]
    worker_id: str | None = None
    messages: list[ChatTurn] = Field(min_length=1, max_length=40)


class AthenaLookBody(BaseModel):
    """Athena Live: one camera picture (JPEG, base64) and the question about it."""

    question: str = Field(min_length=1, max_length=300)
    image: str = Field(min_length=100, max_length=4_000_000)
    previous_question: str | None = Field(default=None, max_length=300)


class MeshMessage(BaseModel):
    """A message that hopped from phone to phone (see BUILD_PLAN.md, "Mesh message format")."""

    msg_id: str
    origin_worker_id: str
    type: str  # help, safe, ping, text, shock, rescue (others are stored but not applied)
    body: str = ""
    zone: str | None = None
    floor: int | None = None
    battery: int | None = None
    created_at: float = 0
    ttl: int = 0
    path: list[str] = []


class MeshUploadBody(BaseModel):
    messages: list[MeshMessage]
