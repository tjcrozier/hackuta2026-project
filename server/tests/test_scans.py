"""Scan compare, the 3D model builder, /scan upload, and hazards."""

import json
import struct

import compare
import demo
from room_to_glb import room_to_glb

YESTERDAY = demo.make_room(3)                    # 6 walls, 2 doors, 1 window, 0 openings
TODAY = demo.make_room(3, extra_opening=True)    # same, plus 1 opening


def upload(client, floor: int, room: dict):
    files = {"model": ("scan.usdz", b"fake usdz bytes"),
             "room_json": ("room.json", json.dumps(room).encode())}
    return client.post("/scan", data={"floor": str(floor)}, files=files)


def ping(client, worker_id: str, floor: int) -> None:
    client.post("/ping", json={"worker_id": worker_id, "zone": "A", "floor": floor,
                               "battery": 80, "moving": True, "source": "internet"})


# ---------- compare.py ----------

def test_count_parts_on_two_sample_scans():
    assert compare.count_parts(YESTERDAY) == {"walls": 6, "doors": 2, "windows": 1,
                                              "openings": 0, "objects": 4}
    assert compare.count_parts(TODAY)["openings"] == 1
    assert compare.count_parts({}) == {"walls": 0, "doors": 0, "windows": 0, "openings": 0,
                                       "objects": 0}


def test_new_opening_is_a_hazard():
    hazards = compare.find_hazards(3, compare.count_parts(YESTERDAY), compare.count_parts(TODAY))
    assert hazards == [("New opening on Floor 3. Check guardrails.",
                        "Fall protection: holes and openings")]


def test_missing_door_and_removed_wall_are_hazards():
    before = {"walls": 6, "doors": 2, "windows": 1, "openings": 0, "objects": 4}
    after = {"walls": 5, "doors": 1, "windows": 1, "openings": 0, "objects": 9}
    assert compare.find_hazards(2, before, after) == [
        ("A door is missing or blocked on Floor 2. Check exits.", "Exit routes"),
        ("A wall was removed on Floor 2. Check the structure.", "Structural stability"),
    ]


def test_same_scan_and_first_scan_have_no_hazards():
    parts = compare.count_parts(YESTERDAY)
    assert compare.find_hazards(3, parts, parts) == []
    assert compare.find_hazards(3, None, parts) == []


# ---------- room_to_glb.py ----------

def test_glb_is_a_valid_file_with_one_mesh_per_part():
    glb = room_to_glb(TODAY)
    magic, version, total = struct.unpack("<4sII", glb[:12])
    assert (magic, version, total) == (b"glTF", 2, len(glb))
    json_length = struct.unpack("<I", glb[12:16])[0]
    gltf = json.loads(glb[20:20 + json_length])
    assert sorted(m["name"] for m in gltf["meshes"]) == [
        "doors", "floor", "objects", "openings", "walls", "windows"]
    walls = next(m for m in gltf["meshes"] if m["name"] == "walls")
    positions = gltf["accessors"][walls["primitives"][0]["attributes"]["POSITION"]]
    assert positions["count"] == 6 * 24  # 6 walls, 24 corners per box
    assert positions["max"][0] - positions["min"][0] > 11  # the floor is about 12 m wide


def test_glb_accepts_nested_transform_and_skips_bad_parts():
    room = {"walls": [
        {"dimensions": [4, 3, 0], "transform": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0],
                                                [2, 1.5, 0, 1]]},
        {"dimensions": "bad"},
        "not a part",
    ]}
    json_length = struct.unpack("<I", room_to_glb(room)[12:16])[0]
    gltf = json.loads(room_to_glb(room)[20:20 + json_length])
    assert gltf["accessors"][0]["count"] == 24


# ---------- /scan and hazards ----------

def test_first_scan_of_a_floor_has_no_hazards(client):
    reply = upload(client, 5, YESTERDAY).json()
    assert reply["hazards"] == []
    assert reply["parts"]["walls"] == 6
    scan = client.get("/state").json()["scans"]["5"]
    assert scan["parts"] == {"walls": 6, "doors": 2, "windows": 1, "openings": 0}
    assert scan["model"].endswith(".glb")
    model = client.get(f"/files/{scan['model']}")
    assert model.status_code == 200
    assert model.content[:4] == b"glTF"


def test_second_scan_with_new_opening_creates_hazard_and_texts(client, join):
    on_floor, other_floor = join("Ana"), join("Ben")
    ping(client, on_floor, 3)
    ping(client, other_floor, 1)
    upload(client, 3, YESTERDAY)

    reply = upload(client, 3, TODAY).json()
    assert [h["text"] for h in reply["hazards"]] == ["New opening on Floor 3. Check guardrails."]

    state = client.get("/state").json()
    hazard = state["hazards"][0]
    assert hazard["status"] == "open"
    assert hazard["before"]["openings"] == 0
    assert hazard["after"]["openings"] == 1

    texts = {(m["to_or_from"], m["body"]) for m in state["messages"]}
    assert texts == {
        ("+10000000000", "BLACK BOX HAZARD: New opening on Floor 3. Check guardrails."),
        ("+15550000001", "BLACK BOX WARNING: New opening on Floor 3. Check guardrails."),
    }


def test_hazard_status_and_warn(client, join):
    ping(client, join("Ana"), 3)
    upload(client, 3, YESTERDAY)
    hazard_id = upload(client, 3, TODAY).json()["hazards"][0]["id"]

    assert client.post(f"/hazards/{hazard_id}/warn").json() == {"ok": True, "sent": 1}
    fixed = client.post(f"/hazards/{hazard_id}", json={"status": "fixed"}).json()
    assert fixed["status"] == "fixed"
    assert client.get("/state").json()["hazards"][0]["status"] == "fixed"

    assert client.post("/hazards/999", json={"status": "fixed"}).status_code == 404
    assert client.post(f"/hazards/{hazard_id}", json={"status": "nope"}).status_code == 422


def test_bad_uploads_are_rejected(client):
    files = {"model": ("scan.usdz", b"x"), "room_json": ("room.json", b"not json")}
    assert client.post("/scan", data={"floor": "3"}, files=files).status_code == 400
    assert client.post("/scan", data={"floor": "3"}, files={"model": ("a", b"x")}).status_code == 400
    assert client.get("/files/..%2Fmain.py").status_code == 404


def test_demo_seed_scans_have_models(client):
    client.post("/demo/reset")
    scans = client.get("/state").json()["scans"]
    assert scans["3"]["parts"] == {"walls": 6, "doors": 2, "windows": 1, "openings": 0}
    assert client.get(f"/files/{scans['3']['model']}").content[:4] == b"glTF"
    # Scanning floor 3 "today" with the extra opening raises the demo hazard.
    assert len(upload(client, 3, TODAY).json()["hazards"]) == 1
