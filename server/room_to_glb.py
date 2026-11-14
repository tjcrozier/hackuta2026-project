"""Turn a RoomPlan JSON scan into a .glb 3D model for the web dashboard.

RoomPlan gives a .usdz file, but browsers need .glb. Instead of converting the file,
we rebuild the room from the JSON: every wall, door, window, opening and object is a
box with a size ("dimensions") and a position ("transform"). No extra software needed.
Openings are drawn in the hazard color so they stand out.
"""

import json
import math
import struct
from typing import Any

# part -> (color r, g, b, minimum thickness in meters)
STYLE = {
    "walls": ((0.42, 0.44, 0.48), 0.10),
    "doors": ((0.08, 0.09, 0.12), 0.16),
    "windows": ((0.02, 0.08, 0.69), 0.16),
    "openings": ((0.54, 0.05, 0.01), 0.18),
    "objects": ((0.25, 0.27, 0.31), 0.0),
    "floor": ((0.72, 0.71, 0.68), 0.0),
}

IDENTITY = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def _matrix(value: Any) -> list[float]:
    """A 4x4 transform as 16 numbers (column by column). RoomPlan may nest it as 4 columns."""
    if isinstance(value, list) and len(value) == 4 and all(isinstance(c, list) for c in value):
        value = [n for column in value for n in column]
    if isinstance(value, list) and len(value) == 16:
        return [float(n) for n in value]
    return IDENTITY


def _box(size: tuple[float, float, float], m: list[float]) -> tuple[list, list]:
    """Corner positions and normals (24 each) of a box of `size`, moved by matrix `m`."""
    half = [s / 2 for s in size]
    positions, normals = [], []
    for axis in range(3):
        u, v = (axis + 1) % 3, (axis + 2) % 3
        for sign in (1, -1):
            corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            if sign < 0:
                corners.reverse()  # keep the face pointing outwards
            normal = [0.0, 0.0, 0.0]
            normal[axis] = float(sign)
            for cu, cv in corners:
                p = [0.0, 0.0, 0.0]
                p[axis], p[u], p[v] = sign * half[axis], cu * half[u], cv * half[v]
                positions.append((
                    m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
                    m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
                    m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
                ))
                n = (m[0] * normal[0] + m[4] * normal[1] + m[8] * normal[2],
                     m[1] * normal[0] + m[5] * normal[1] + m[9] * normal[2],
                     m[2] * normal[0] + m[6] * normal[1] + m[10] * normal[2])
                length = math.sqrt(sum(c * c for c in n)) or 1.0
                normals.append(tuple(c / length for c in n))
    return positions, normals


def _boxes(room: dict[str, Any]) -> dict[str, list[tuple[list, list]]]:
    """Every part of the room as boxes, grouped by part name."""
    groups: dict[str, list[tuple[list, list]]] = {}
    for part, (_, min_depth) in STYLE.items():
        for item in room.get(part) or []:
            size = item.get("dimensions") if isinstance(item, dict) else None
            if not (isinstance(size, list) and len(size) == 3):
                continue
            width, height, depth = (float(s) for s in size)
            if width <= 0 or height <= 0:
                continue
            box = _box((width, height, max(depth, min_depth)), _matrix(item.get("transform")))
            groups.setdefault(part, []).append(box)

    # A thin floor slab under everything, so the model does not float in space.
    points = [p for boxes in groups.values() for positions, _ in boxes for p in positions]
    if points:
        xs, ys, zs = zip(*points, strict=True)
        slab = IDENTITY.copy()
        slab[12], slab[13], slab[14] = (min(xs) + max(xs)) / 2, min(ys) - 0.03, (min(zs) + max(zs)) / 2
        size = (max(xs) - min(xs) + 0.4, 0.06, max(zs) - min(zs) + 0.4)
        groups["floor"] = [_box(size, slab)]
    return groups


def room_to_glb(room: dict[str, Any]) -> bytes:
    """Build the .glb file bytes. Raises ValueError if the scan has nothing to draw."""
    groups = _boxes(room)
    if not groups:
        raise ValueError("The scan has no walls or objects to draw.")

    binary = bytearray()
    gltf: dict[str, Any] = {
        "asset": {"version": "2.0", "generator": "Black Box"},
        "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [],
        "accessors": [], "bufferViews": [], "buffers": [],
    }

    def add_view(data: bytes, target: int) -> int:
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(binary),
                                    "byteLength": len(data), "target": target})
        binary.extend(data)
        return len(gltf["bufferViews"]) - 1

    for part, boxes in groups.items():
        positions = [p for box_positions, _ in boxes for p in box_positions]
        normals = [n for _, box_normals in boxes for n in box_normals]
        indices = []
        for face in range(len(positions) // 4):  # two triangles per face
            a = face * 4
            indices += [a, a + 1, a + 2, a, a + 2, a + 3]

        views = [
            add_view(b"".join(struct.pack("<3f", *p) for p in positions), 34962),
            add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962),
            add_view(struct.pack(f"<{len(indices)}I", *indices), 34963),
        ]
        first = len(gltf["accessors"])
        xs, ys, zs = zip(*positions, strict=True)
        gltf["accessors"] += [
            {"bufferView": views[0], "componentType": 5126, "count": len(positions),
             "type": "VEC3", "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
            {"bufferView": views[1], "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {"bufferView": views[2], "componentType": 5125, "count": len(indices),
             "type": "SCALAR"},
        ]
        red, green, blue = STYLE[part][0]
        gltf["materials"].append({
            "name": part, "doubleSided": True,
            "pbrMetallicRoughness": {"baseColorFactor": [red, green, blue, 1.0],
                                     "metallicFactor": 0.0, "roughnessFactor": 0.9},
        })
        gltf["meshes"].append({"name": part, "primitives": [{
            "attributes": {"POSITION": first, "NORMAL": first + 1},
            "indices": first + 2, "material": len(gltf["materials"]) - 1}]})
        gltf["nodes"].append({"name": part, "mesh": len(gltf["meshes"]) - 1})
        gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)

    gltf["buffers"].append({"byteLength": len(binary)})
    json_chunk = json.dumps(gltf, separators=(",", ":")).encode()
    json_chunk += b" " * (-len(json_chunk) % 4)  # chunks must be a multiple of 4 bytes
    binary.extend(b"\0" * (-len(binary) % 4))
    total = 12 + 8 + len(json_chunk) + 8 + len(binary)
    return (struct.pack("<4sII", b"glTF", 2, total)
            + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk
            + struct.pack("<I4s", len(binary), b"BIN\0") + bytes(binary))
