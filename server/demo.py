"""Demo seed data: 14 workers on 3 floors and yesterday's scans for floors 1-3."""

import json
import math
from typing import Any

import compare
import config
import db
import scans

# (name, floor, zone, battery)
DEMO_WORKERS = [
    ("Sajid H.", 3, "B", 64),
    ("Maria G.", 3, "A", 81),
    ("Devon K.", 3, "C", 47),
    ("Priya N.", 3, "B", 92),
    ("Tomas R.", 3, "A", 58),
    ("Aisha B.", 2, "A", 73),
    ("Luis M.", 2, "B", 39),
    ("Hannah W.", 2, "C", 88),
    ("Omar F.", 2, "B", 66),
    ("Chen L.", 2, "C", 51),
    ("Grace O.", 1, "A", 95),
    ("Marcus T.", 1, "B", 70),
    ("Elena V.", 1, "C", 44),
    ("Jamal S.", 1, "A", 83),
]

# floor -> (walls, doors, windows, objects). Yesterday's scans have no openings.
DEMO_SCANS = {1: (8, 3, 2, 5), 2: (7, 2, 2, 3), 3: (6, 2, 1, 4)}

# The demo floor is a 12 m x 8 m rectangle, 3 m high.
_WIDE, _DEEP, _HIGH = 12.0, 8.0, 3.0


def _part(category: str, size: tuple[float, float, float], x: float, y: float, z: float,
          angle: float = 0.0) -> dict[str, Any]:
    """One RoomPlan-style part: a size and a 4x4 transform (turned `angle` around up)."""
    cos, sin = math.cos(angle), math.sin(angle)
    return {"category": {category: {}}, "dimensions": list(size),
            "transform": [cos, 0, -sin, 0, 0, 1, 0, 0, sin, 0, cos, 0, x, y, z, 1]}


def make_room(floor: int, extra_opening: bool = False) -> dict[str, Any]:
    """A simple RoomPlan-style JSON for a demo floor. Same shape as a real scan's JSON."""
    walls, doors, windows, objects = DEMO_SCANS.get(floor, DEMO_SCANS[3])
    half_w, half_d, turn = _WIDE / 2, _DEEP / 2, math.pi / 2
    room: dict[str, Any] = {"walls": [], "doors": [], "windows": [], "openings": [], "objects": []}

    # Four outer walls: north, south, west, east.
    room["walls"] += [
        _part("wall", (_WIDE, _HIGH, 0), 0, _HIGH / 2, -half_d),
        _part("wall", (_WIDE, _HIGH, 0), 0, _HIGH / 2, half_d),
        _part("wall", (_DEEP, _HIGH, 0), -half_w, _HIGH / 2, 0, turn),
        _part("wall", (_DEEP, _HIGH, 0), half_w, _HIGH / 2, 0, turn),
    ]
    # Inside walls split the floor into rooms.
    for i in range(walls - 4):
        x = -half_w + _WIDE * (i + 1) / (walls - 3)
        room["walls"].append(_part("wall", (_DEEP * 0.55, _HIGH, 0), x, _HIGH / 2,
                                   -half_d + _DEEP * 0.275, turn))
    for i in range(doors):  # doors on the south wall
        x = -half_w + _WIDE * (i + 1) / (doors + 1)
        room["doors"].append(_part("door", (0.9, 2.1, 0), x, 1.05, half_d))
    for i in range(windows):  # windows on the north wall
        x = -half_w + _WIDE * (i + 1) / (windows + 1)
        room["windows"].append(_part("window", (1.4, 1.1, 0), x, 1.6, -half_d))
    for i in range(objects):
        x = -half_w + _WIDE * (i + 0.5) / objects
        room["objects"].append(_part("storage", (1.0, 0.8, 0.6), x, 0.4, half_d - 1.4))
    if extra_opening:  # the new hazard: an opening on the east side
        room["openings"].append(_part("opening", (1.8, 2.2, 0), half_w, 1.1, 1.0, turn))
    return room


def seed() -> None:
    """Fill an empty database with the demo site."""
    workers = DEMO_WORKERS if config.DEMO_WORKERS else []
    for index, (name, floor, zone, battery) in enumerate(workers, start=1):
        worker_id = db.add_worker(name, f"{DEMO_PHONE_PREFIX}{index:04d}", config.SITE_CODE)
        db.add_ping(worker_id, zone, floor, battery, None, None, True, "internet")

    yesterday = db.now() - 24 * 3600
    for floor in DEMO_SCANS:
        room = make_room(floor)
        base = f"demo-floor{floor}"
        (scans.scans_dir() / f"{base}.json").write_text(json.dumps(room))
        glb = scans.write_glb(room, f"{base}.glb")
        # There is no real .usdz for the demo floors; the name is only a label.
        db.add_scan(floor, f"{base}.usdz", glb, f"{base}.json", compare.count_parts(room),
                    ts=yesterday)


DEMO_PHONE_PREFIX = "+1555010"


def refresh_pings() -> int:
    """Demo mode only: the 14 demo workers have no real phone, so ping for them.

    Each one pings again from where it last was, so the dashboard shows "last ping 20 s ago"
    instead of "phone lost". Real workers are never touched. Returns how many pinged.
    """
    count = 0
    for worker in db.active_workers():
        if not worker["phone"].startswith(DEMO_PHONE_PREFIX):
            continue
        ping = db.last_ping(worker["id"])
        if ping is None:
            continue
        db.add_ping(worker["id"], ping["zone"], ping["floor"], ping["battery"], None, None,
                    True, ping["source"])
        count += 1
    return count


def reset() -> None:
    """Wipe everything and seed again."""
    db.clear_all()
    seed()
