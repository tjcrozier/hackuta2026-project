"""Saving scan files and finding hazards in a new scan."""

import json
import logging
from pathlib import Path
from typing import Any

import compare
import config
import db
from room_to_glb import room_to_glb

log = logging.getLogger("blackbox.scans")

MEDIA_TYPES = {".glb": "model/gltf-binary", ".usdz": "model/vnd.usdz+zip",
               ".json": "application/json"}


def scans_dir() -> Path:
    folder = Path(config.SCANS_DIR)
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def file_path(name: str) -> Path | None:
    """The stored file with this name, or None. Names with folders in them are refused."""
    if Path(name).name != name:
        return None
    path = scans_dir() / name
    return path if path.is_file() else None


def write_glb(room: dict[str, Any], name: str) -> str | None:
    """Build the web 3D model. Returns the file name, or None if it could not be built."""
    try:
        (scans_dir() / name).write_bytes(room_to_glb(room))
        return name
    except Exception as error:  # noqa: BLE001 - a bad model must never block the hazard alert
        log.warning("Could not build %s: %s", name, error)
        return None


def save_scan(floor: int, model: bytes, room_json: bytes) -> dict[str, Any]:
    """Store a scan, compare it with the floor's last scan, and create hazards.

    Returns {scan_id, parts, hazards}. Raises ValueError if room_json is not valid.
    """
    try:
        room = json.loads(room_json)
    except ValueError as error:
        raise ValueError("room_json is not valid JSON.") from error
    if not isinstance(room, dict):
        raise ValueError("room_json must be a JSON object.")  # noqa: TRY004 - becomes a 400

    parts = compare.count_parts(room)
    before = db.scan_parts(db.last_scan(floor))

    base = f"floor{floor}-{int(db.now() * 1000)}"
    (scans_dir() / f"{base}.usdz").write_bytes(model)
    (scans_dir() / f"{base}.json").write_bytes(room_json)
    glb = write_glb(room, f"{base}.glb")
    scan_id = db.add_scan(floor, f"{base}.usdz", glb, f"{base}.json", parts)

    hazards = []
    if config.FEATURE_SCAN_COMPARE:
        for text, osha_topic in compare.find_hazards(floor, before, parts):
            hazard_id = db.add_hazard(floor, text, osha_topic, scan_id)
            hazards.append(db.hazard_dict(db.get_hazard(hazard_id)))
    return {"scan_id": scan_id, "parts": parts, "hazards": hazards}
