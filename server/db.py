"""SQLite storage for Cycl0ps. One shared connection, small helper functions."""

import re
import sqlite3
import time
from typing import Any

import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS workers (
    id TEXT PRIMARY KEY, name TEXT, phone TEXT, site_code TEXT,
    joined_at REAL, active INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS pings (
    id INTEGER PRIMARY KEY AUTOINCREMENT, worker_id TEXT, zone TEXT, floor INTEGER,
    battery INTEGER, lat REAL, lng REAL, moving INTEGER, source TEXT, ts REAL);
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT, worker_id TEXT, type TEXT, ts REAL);
CREATE TABLE IF NOT EXISTS rescue (
    id INTEGER PRIMARY KEY AUTOINCREMENT, active INTEGER, reason TEXT,
    started_at REAL, ended_at REAL);
CREATE TABLE IF NOT EXISTS checkins (
    rescue_id INTEGER, worker_id TEXT, status TEXT, note TEXT, ts REAL,
    PRIMARY KEY (rescue_id, worker_id));
CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY AUTOINCREMENT, floor INTEGER, model_file TEXT, glb_file TEXT,
    json_file TEXT, walls INTEGER, doors INTEGER, windows INTEGER, openings INTEGER,
    objects INTEGER, ts REAL);
CREATE TABLE IF NOT EXISTS hazards (
    id INTEGER PRIMARY KEY AUTOINCREMENT, floor INTEGER, text TEXT, osha_topic TEXT,
    status TEXT DEFAULT 'open', scan_id INTEGER, ts REAL);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT, direction TEXT, to_or_from TEXT, body TEXT,
    channel TEXT, ts REAL);
CREATE TABLE IF NOT EXISTS mesh_seen (msg_id TEXT PRIMARY KEY, ts REAL);
"""

TABLES = ["workers", "pings", "events", "rescue", "checkins", "scans", "hazards",
          "messages", "mesh_seen"]

# Check-ins sent while no rescue is running are stored under this rescue id.
NO_RESCUE = 0

_conn: sqlite3.Connection | None = None


def now() -> float:
    """Current time in seconds. Tests replace this to control the clock."""
    return time.time()


def init(path: str) -> None:
    """Open the database file and create the tables."""
    global _conn
    if _conn is not None:
        _conn.close()
    _conn = sqlite3.connect(path, check_same_thread=False)
    _conn.row_factory = sqlite3.Row
    _conn.executescript(SCHEMA)
    _conn.commit()


def query(sql: str, args: tuple = ()) -> list[sqlite3.Row]:
    assert _conn is not None, "call db.init() first"
    return _conn.execute(sql, args).fetchall()


def run(sql: str, args: tuple = ()) -> int:
    """Run a write and return the new row id."""
    assert _conn is not None, "call db.init() first"
    cur = _conn.execute(sql, args)
    _conn.commit()
    return cur.lastrowid or 0


def clear_all() -> None:
    for table in TABLES:
        run(f"DELETE FROM {table}")
    run("DELETE FROM sqlite_sequence")  # restart the id counters


# ---------- workers ----------

def phone_key(phone: str) -> str:
    """Last 10 digits, so '+1 (555) 010-0001' and '5550100001' match."""
    return re.sub(r"\D", "", phone)[-10:]


def find_worker_by_phone(phone: str) -> sqlite3.Row | None:
    key = phone_key(phone)
    if not key:
        return None
    for row in query("SELECT * FROM workers"):
        if phone_key(row["phone"]) == key:
            return row
    return None


def get_worker(worker_id: str) -> sqlite3.Row | None:
    rows = query("SELECT * FROM workers WHERE id = ?", (worker_id,))
    return rows[0] if rows else None


def add_worker(name: str, phone: str, site_code: str) -> str:
    """Add a worker, or re-activate the one who already joined with this phone."""
    existing = find_worker_by_phone(phone)
    if existing:
        run("UPDATE workers SET name = ?, active = 1 WHERE id = ?", (name, existing["id"]))
        return existing["id"]
    worker_id = f"w{query('SELECT COUNT(*) AS n FROM workers')[0]['n'] + 1}"
    run("INSERT INTO workers (id, name, phone, site_code, joined_at, active) "
        "VALUES (?, ?, ?, ?, ?, 1)", (worker_id, name, phone, site_code, now()))
    return worker_id


def set_active(worker_id: str, active: bool) -> None:
    """Start shift (active) or end shift (not shown on the dashboard)."""
    run("UPDATE workers SET active = ? WHERE id = ?", (int(active), worker_id))


def is_empty() -> bool:
    """True for a brand-new database (no workers and no scans yet)."""
    return not query("SELECT 1 FROM workers LIMIT 1") and not query("SELECT 1 FROM scans LIMIT 1")


def active_workers() -> list[sqlite3.Row]:
    return query("SELECT * FROM workers WHERE active = 1 ORDER BY joined_at, id")


# ---------- pings and events ----------

def add_ping(worker_id: str, zone: str | None, floor: int | None, battery: int | None,
             lat: float | None, lng: float | None, moving: bool, source: str,
             ts: float | None = None) -> None:
    run("INSERT INTO pings (worker_id, zone, floor, battery, lat, lng, moving, source, ts) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (worker_id, zone, floor, battery, lat, lng, int(moving), source, ts or now()))


def last_ping(worker_id: str) -> sqlite3.Row | None:
    rows = query("SELECT * FROM pings WHERE worker_id = ? ORDER BY ts DESC, id DESC LIMIT 1",
                 (worker_id,))
    return rows[0] if rows else None


def add_event(worker_id: str, event_type: str) -> None:
    run("INSERT INTO events (worker_id, type, ts) VALUES (?, ?, ?)",
        (worker_id, event_type, now()))


def phones_with_shock(window_sec: float) -> int:
    """How many different workers sent a shock in the last `window_sec` seconds."""
    rows = query("SELECT COUNT(DISTINCT worker_id) AS n FROM events "
                 "WHERE type = 'shock' AND ts >= ?", (now() - window_sec,))
    return rows[0]["n"]


# ---------- rescue and check-ins ----------

def rescue_dict(row: sqlite3.Row | None) -> dict[str, Any]:
    if row is None:
        return {"id": None, "active": False, "reason": None, "started_at": None,
                "ended_at": None}
    return {"id": row["id"], "active": bool(row["active"]), "reason": row["reason"],
            "started_at": _int(row["started_at"]), "ended_at": _int(row["ended_at"])}


def active_rescue() -> sqlite3.Row | None:
    rows = query("SELECT * FROM rescue WHERE active = 1 ORDER BY id DESC LIMIT 1")
    return rows[0] if rows else None


def last_rescue() -> sqlite3.Row | None:
    rows = query("SELECT * FROM rescue ORDER BY id DESC LIMIT 1")
    return rows[0] if rows else None


def start_rescue(reason: str) -> sqlite3.Row:
    """Create the rescue and set every active worker's check-in to 'none'."""
    rescue_id = run("INSERT INTO rescue (active, reason, started_at) VALUES (1, ?, ?)",
                    (reason, now()))
    for worker in active_workers():
        set_checkin(rescue_id, worker["id"], "none", None)
    return query("SELECT * FROM rescue WHERE id = ?", (rescue_id,))[0]


def stop_rescue() -> None:
    run("UPDATE rescue SET active = 0, ended_at = ? WHERE active = 1", (now(),))


def set_checkin(rescue_id: int, worker_id: str, status: str, note: str | None) -> None:
    run("INSERT INTO checkins (rescue_id, worker_id, status, note, ts) VALUES (?, ?, ?, ?, ?) "
        "ON CONFLICT (rescue_id, worker_id) DO UPDATE SET "
        "status = excluded.status, note = excluded.note, ts = excluded.ts",
        (rescue_id, worker_id, status, note, now()))


# ---------- scans and hazards ----------

def add_scan(floor: int, model_file: str, glb_file: str | None, json_file: str,
             parts: dict[str, int], ts: float | None = None) -> int:
    return run("INSERT INTO scans (floor, model_file, glb_file, json_file, walls, doors, "
               "windows, openings, objects, ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
               (floor, model_file, glb_file, json_file, parts["walls"], parts["doors"],
                parts["windows"], parts["openings"], parts["objects"], ts or now()))


def scan_parts(scan: sqlite3.Row | None) -> dict[str, int] | None:
    if scan is None:
        return None
    return {part: scan[part] for part in ("walls", "doors", "windows", "openings", "objects")}


def last_scan(floor: int, before_id: int | None = None) -> sqlite3.Row | None:
    """Newest scan of a floor. With `before_id`, the newest one older than that scan."""
    rows = query("SELECT * FROM scans WHERE floor = ? AND id < ? ORDER BY id DESC LIMIT 1",
                 (floor, before_id if before_id is not None else 1 << 62))
    return rows[0] if rows else None


def get_scan(scan_id: int | None) -> sqlite3.Row | None:
    rows = query("SELECT * FROM scans WHERE id = ?", (scan_id,))
    return rows[0] if rows else None


def add_hazard(floor: int, text: str, osha_topic: str, scan_id: int) -> int:
    return run("INSERT INTO hazards (floor, text, osha_topic, status, scan_id, ts) "
               "VALUES (?, ?, ?, 'open', ?, ?)", (floor, text, osha_topic, scan_id, now()))


def get_hazard(hazard_id: int) -> sqlite3.Row | None:
    rows = query("SELECT * FROM hazards WHERE id = ?", (hazard_id,))
    return rows[0] if rows else None


def set_hazard_status(hazard_id: int, status: str) -> None:
    run("UPDATE hazards SET status = ? WHERE id = ?", (status, hazard_id))


def hazard_dict(hazard: sqlite3.Row) -> dict[str, Any]:
    """A hazard for the API, with the part counts before and after the scan that found it."""
    scan = get_scan(hazard["scan_id"])
    before = last_scan(hazard["floor"], before_id=scan["id"]) if scan else None
    return {"id": hazard["id"], "floor": hazard["floor"], "text": hazard["text"],
            "osha_topic": hazard["osha_topic"], "status": hazard["status"],
            "ts": _int(hazard["ts"]), "before": scan_parts(before), "after": scan_parts(scan)}


def workers_on_floor(floor: int) -> list[sqlite3.Row]:
    """Active workers whose last ping was on this floor."""
    on_floor = []
    for worker in active_workers():
        ping = last_ping(worker["id"])
        if ping and ping["floor"] == floor:
            on_floor.append(worker)
    return on_floor


# ---------- mesh ----------

def mesh_first_time(msg_id: str) -> bool:
    """Remember a mesh message id. False if it was already uploaded by another phone."""
    if query("SELECT 1 FROM mesh_seen WHERE msg_id = ?", (msg_id,)):
        return False
    run("INSERT INTO mesh_seen (msg_id, ts) VALUES (?, ?)", (msg_id, now()))
    return True


# ---------- messages ----------

def add_message(direction: str, to_or_from: str, body: str, channel: str) -> None:
    run("INSERT INTO messages (direction, to_or_from, body, channel, ts) VALUES (?, ?, ?, ?, ?)",
        (direction, to_or_from, body, channel, now()))


# ---------- snapshot ----------

def _int(value: float | None) -> int | None:
    return None if value is None else int(value)


def snapshot() -> dict[str, Any]:
    """The full state sent to the dashboard (GET /state and WS /live)."""
    rescue = active_rescue()
    rescue_id = rescue["id"] if rescue else NO_RESCUE
    statuses = {row["worker_id"]: row["status"] for row in
                query("SELECT worker_id, status FROM checkins WHERE rescue_id = ?", (rescue_id,))}

    workers = []
    for worker in active_workers():
        ping = last_ping(worker["id"])
        workers.append({
            "id": worker["id"],
            "name": worker["name"],
            "zone": ping["zone"] if ping else None,
            "floor": ping["floor"] if ping else None,
            "battery": ping["battery"] if ping else None,
            "last_ping": _int(ping["ts"]) if ping else None,
            "moving": bool(ping["moving"]) if ping else False,
            "source": ping["source"] if ping else None,
            "status": statuses.get(worker["id"], "none"),
            "phone_lost": bool(ping) and now() - ping["ts"] > config.PHONE_LOST_SEC,
        })

    hazards = [hazard_dict(h) for h in query("SELECT * FROM hazards ORDER BY ts DESC, id DESC")]

    # Newest scan per floor (rows come oldest first, so later rows overwrite).
    scans = {}
    for s in query("SELECT * FROM scans ORDER BY ts, id"):
        scans[str(s["floor"])] = {
            "model": s["glb_file"] or s["model_file"],
            "ts": _int(s["ts"]),
            "parts": {"walls": s["walls"], "doors": s["doors"], "windows": s["windows"],
                      "openings": s["openings"]},
        }

    messages = [{"direction": m["direction"], "to_or_from": m["to_or_from"], "body": m["body"],
                 "ts": _int(m["ts"])}
                for m in query("SELECT * FROM messages ORDER BY id DESC LIMIT 50")]

    return {
        "site": {"name": config.SITE_NAME, "code": config.SITE_CODE},
        "rescue": {"active": rescue is not None,
                   "reason": rescue["reason"] if rescue else None,
                   "started_at": _int(rescue["started_at"]) if rescue else None},
        "workers": workers,
        "hazards": hazards,
        "scans": scans,
        "messages": messages,
    }
