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
