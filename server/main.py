"""Cycl0ps server: workers, pings, events, Rescue Mode, live snapshot."""

import asyncio
import contextlib
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

import athena
import config
import db
import demo
import rules
import scans
from models import (
    AthenaBody,
    AthenaLookBody,
    CheckinBody,
    EventBody,
    HazardBody,
    JoinBody,
    MeshMessage,
    MeshUploadBody,
    PingBody,
    RescueStartBody,
)
from senders import get_sender

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("blackbox")


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init(os.environ.get("BB_DB_PATH", config.DB_PATH))
    if config.DEMO_MODE and db.is_empty():
        demo.seed()
    keep_alive = asyncio.create_task(demo_keep_alive()) if config.DEMO_MODE else None
    yield
    if keep_alive:
        keep_alive.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await keep_alive


async def demo_keep_alive() -> None:
    """Demo mode: ping for the demo workers every 30 s so they never look "phone lost"."""
    while True:
        await asyncio.sleep(30)
        if demo.refresh_pings():
            await broadcast()


app = FastAPI(title="Cycl0ps", lifespan=lifespan)
# The web dashboard may run from another address while developing (flutter run -d chrome).
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"],
                   allow_headers=["*"])

live_sockets: set[WebSocket] = set()


async def broadcast() -> None:
    """Push the fresh snapshot to every open dashboard."""
    snapshot = db.snapshot()
    for socket in list(live_sockets):
        try:
            await socket.send_json(snapshot)
        except (WebSocketDisconnect, RuntimeError):  # the dashboard went away
            live_sockets.discard(socket)


def worker_or_404(worker_id: str) -> Any:
    worker = db.get_worker(worker_id)
    if worker is None:
        raise HTTPException(404, "Unknown worker. Join the site first.")
    return worker


def where(worker_id: str) -> str:
    """'Floor 3, Zone B' from the worker's last ping."""
    ping = db.last_ping(worker_id)
    floor = ping["floor"] if ping and ping["floor"] is not None else "?"
    zone = ping["zone"] if ping and ping["zone"] else "?"
    return f"Floor {floor}, Zone {zone}"


async def start_rescue(reason: str) -> dict[str, Any]:
    """Start Rescue Mode (once) and text every active worker."""
    existing = db.active_rescue()
    if existing:
        return db.rescue_dict(existing)
    rescue = db.start_rescue(reason)
    log.warning("RESCUE MODE STARTED: %s", reason)
    sender = get_sender()
    for worker in db.active_workers():
        await sender.send(worker["phone"],
                          f"CYCL0PS EMERGENCY. {worker['name']}, are you OK? "
                          "Reply 1 if safe, 2 if you need help.")
    return db.rescue_dict(rescue)


async def apply_checkin(worker: Any, status: str, note: str | None) -> None:
    """Save a check-in. Outside Rescue Mode, a 'help' also texts the supervisor."""
    rescue = db.active_rescue()
    db.set_checkin(rescue["id"] if rescue else db.NO_RESCUE, worker["id"], status, note)
    if status == "help" and rescue is None:
        await get_sender().send(config.SUPERVISOR_PHONE,
                                f"{worker['name']} needs help. {where(worker['id'])}.")


# ---------- endpoints ----------

@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}


@app.post("/workers/join")
async def join(body: JoinBody) -> dict[str, str]:
    if body.site_code.strip().upper() != config.SITE_CODE.upper():
        raise HTTPException(400, "Wrong site code.")
    worker_id = db.add_worker(body.name.strip(), body.phone.strip(), config.SITE_CODE)
    await broadcast()
    return {"worker_id": worker_id}


@app.post("/ping")
async def ping(body: PingBody) -> dict[str, Any]:
    worker = worker_or_404(body.worker_id)
    if not worker["active"]:
        db.set_active(body.worker_id, True)  # pinging again = the shift started again
    db.add_ping(body.worker_id, body.zone, body.floor, body.battery, body.lat, body.lng,
                body.moving, body.source)
    await broadcast()
    rescue = db.active_rescue()
    return {"rescue_active": rescue is not None, "rescue_id": rescue["id"] if rescue else None}


@app.post("/workers/{worker_id}/end_shift")
async def end_shift(worker_id: str) -> dict[str, bool]:
    """The worker tapped End shift: hide them from the dashboard until they ping again."""
    worker_or_404(worker_id)
    db.set_active(worker_id, False)
    await broadcast()
    return {"ok": True}


@app.post("/event")
async def event(body: EventBody) -> dict[str, bool]:
    worker = worker_or_404(body.worker_id)
    db.add_event(body.worker_id, body.type)

    if body.type == "shock" and db.active_rescue() is None:
        phones = db.phones_with_shock(config.COLLAPSE_WINDOW_SEC)
        if rules.is_collapse(phones, config.COLLAPSE_PHONES):
            await start_rescue(f"impact on {phones} phones")

    if body.type == "fall_alert":
        await get_sender().send(config.SUPERVISOR_PHONE,
                                f"Possible fall: {worker['name']}, {where(worker['id'])}.")

    # The phone only sends no_move after the worker did not answer "Are you OK?".
    if body.type == "no_move":
        await get_sender().send(config.SUPERVISOR_PHONE,
                                f"No movement and no answer: {worker['name']}, "
                                f"{where(worker['id'])}.")

    await broadcast()
    return {"rescue_active": db.active_rescue() is not None}


@app.post("/rescue/start")
async def rescue_start(body: RescueStartBody) -> dict[str, Any]:
    rescue = await start_rescue(body.reason)
    await broadcast()
    return rescue


@app.post("/rescue/stop")
async def rescue_stop() -> dict[str, Any]:
    db.stop_rescue()
    await broadcast()
    return db.rescue_dict(db.last_rescue())


@app.post("/checkin")
async def checkin(body: CheckinBody) -> dict[str, bool]:
    worker = worker_or_404(body.worker_id)
    await apply_checkin(worker, body.status, body.note)
    await broadcast()
    return {"ok": True}


@app.post("/chert/webhook")
async def chert_webhook(request: Request) -> dict[str, bool]:
    """A worker replied to a text. "1" = safe, "2" = help, other text = help + note."""
    try:
        payload = await request.json()
    except ValueError:
        payload = {}
    sender, text = rules.extract_inbound(payload if isinstance(payload, dict) else {})
    if not sender or text is None:
        log.warning("Chert webhook: could not find sender/text in %s", payload)
        return {"ok": True}

    db.add_message("in", sender, text, "chert")
    worker = db.find_worker_by_phone(sender)
    if worker:
        status, note = rules.parse_reply(text)
        await apply_checkin(worker, status, note)
    await broadcast()
    return {"ok": True}


@app.post("/scan")
async def scan_upload(request: Request) -> dict[str, Any]:
    """Supervisor uploads a floor scan: `floor`, `model` (.usdz) and `room_json`."""
    form = await request.form()
    try:
        floor = int(str(form.get("floor")))
    except ValueError as error:
        raise HTTPException(400, "floor must be a number.") from error

    async def read(field: str) -> bytes:
        value = form.get(field)
        if value is None:
            raise HTTPException(400, f"Missing field: {field}.")
        return value.encode() if isinstance(value, str) else await value.read()

    try:
        result = scans.save_scan(floor, await read("model"), await read("room_json"))
    except ValueError as error:
        raise HTTPException(400, str(error)) from error

    # Text the supervisor and the workers on that floor about each new hazard.
    sender = get_sender()
    for hazard in result["hazards"]:
        await sender.send(config.SUPERVISOR_PHONE, f"CYCL0PS HAZARD: {hazard['text']}")
        await warn_floor(hazard)
    await broadcast()
    return result


async def warn_floor(hazard: dict[str, Any]) -> int:
    """Text every worker whose last ping was on the hazard's floor. Returns how many."""
    workers = db.workers_on_floor(hazard["floor"])
    sender = get_sender()
    for worker in workers:
        await sender.send(worker["phone"], f"CYCL0PS WARNING: {hazard['text']}")
    return len(workers)


def hazard_or_404(hazard_id: int) -> Any:
    hazard = db.get_hazard(hazard_id)
    if hazard is None:
        raise HTTPException(404, "Unknown hazard.")
    return hazard


@app.post("/hazards/{hazard_id}")
async def hazard_update(hazard_id: int, body: HazardBody) -> dict[str, Any]:
    """Mark a hazard open, fixed or false_alarm."""
    hazard_or_404(hazard_id)
    db.set_hazard_status(hazard_id, body.status)
    await broadcast()
    return db.hazard_dict(hazard_or_404(hazard_id))


@app.post("/hazards/{hazard_id}/warn")
async def hazard_warn(hazard_id: int) -> dict[str, Any]:
    """Warn the workers on the hazard's floor again (supervisor button)."""
    sent = await warn_floor(db.hazard_dict(hazard_or_404(hazard_id)))
    await broadcast()
    return {"ok": True, "sent": sent}


@app.get("/files/{name}")
def files(name: str) -> FileResponse:
    """Scan files (.glb for the web 3D view, .usdz, .json)."""
    path = scans.file_path(name)
    if path is None:
        raise HTTPException(404, "File not found.")
    return FileResponse(path, media_type=scans.MEDIA_TYPES.get(path.suffix))


async def apply_mesh_message(message: MeshMessage) -> None:
    """Use one mesh message as if the phone had reached the server itself."""
    if message.type == "rescue":  # phones started Rescue Mode on their own while offline
        await start_rescue(message.body or "started offline over the mesh")
        return
    worker = db.get_worker(message.origin_worker_id)
    if worker is None:
        return
    if message.type in ("help", "safe", "ping") and message.floor is not None:
        # The position travelled with the message. It shows on the dashboard as "via mesh".
        db.add_ping(worker["id"], message.zone, message.floor, message.battery, None, None,
                    False, "mesh", ts=message.created_at or None)
    if message.type in ("help", "safe"):
        await apply_checkin(worker, message.type, message.body or None)
    if message.type in ("help", "safe", "text"):
        db.add_message("in", worker["name"], message.body, "mesh")


@app.post("/mesh/upload")
async def mesh_upload(body: MeshUploadBody) -> dict[str, int]:
    """A phone with internet hands over the mesh messages it collected."""
    if not config.FEATURE_MESH:
        raise HTTPException(403, "The mesh is turned off (FEATURE_MESH=false).")
    accepted = duplicates = 0
    # Oldest first, so a later "safe" wins over an earlier "help".
    for message in sorted(body.messages, key=lambda m: m.created_at):
        if not db.mesh_first_time(message.msg_id):
            duplicates += 1
            continue
        accepted += 1
        await apply_mesh_message(message)
    if accepted:
        await broadcast()
    return {"accepted": accepted, "duplicates": duplicates}


@app.get("/state")
def state() -> dict[str, Any]:
    return db.snapshot()


@app.post("/athena/chat")
async def athena_chat(body: AthenaBody) -> dict[str, str]:
    """Athena's reply to the chat so far, using only what this role may know about the site."""
    if body.role == "worker":
        worker_or_404(body.worker_id or "")
    messages = [turn.model_dump() for turn in body.messages]
    text, source = await athena.reply(messages, db.snapshot(), body.role, body.worker_id)
    return {"reply": text, "source": source}


@app.post("/athena/look")
async def athena_look(body: AthenaLookBody) -> dict[str, str]:
    """Athena Live: answer a question about one camera picture. The picture is not stored."""
    if not athena.picture_ok(body.image):
        raise HTTPException(400, "The picture must be a JPEG or PNG.")
    text, source = await athena.look(body.image, body.question, body.previous_question)
    return {"reply": text, "source": source}


@app.post("/demo/reset")
async def demo_reset() -> dict[str, bool]:
    if not config.DEMO_MODE:
        raise HTTPException(403, "Demo reset is only allowed when DEMO_MODE=true.")
    demo.reset()
    await broadcast()
    return {"ok": True}


@app.websocket("/live")
async def live(socket: WebSocket) -> None:
    await socket.accept()
    live_sockets.add(socket)
    try:
        await socket.send_json(db.snapshot())
        while True:  # we only push; this just waits until the dashboard disconnects
            await socket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        live_sockets.discard(socket)


# ---------- web dashboard ----------
# The built Flutter web app (run ./build_web.sh). Dashboard: /app/#/dashboard,
# rescuer page: /app/#/rescue.
WEB_DIR = Path(__file__).parent / "static" / "app"


@app.get("/")
def root() -> RedirectResponse:
    """Open the dashboard if it is built, otherwise the API docs."""
    return RedirectResponse("/app/" if WEB_DIR.is_dir() else "/docs")


if WEB_DIR.is_dir():
    app.mount("/app", StaticFiles(directory=WEB_DIR, html=True), name="app")
