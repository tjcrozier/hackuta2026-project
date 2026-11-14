"""Scan compare: count the parts in a RoomPlan scan and find new hazards."""

from typing import Any

PARTS = ("walls", "doors", "windows", "openings", "objects")


def count_parts(room: dict[str, Any]) -> dict[str, int]:
    """How many walls, doors, windows, openings and objects a RoomPlan JSON has."""
    return {part: len(room.get(part) or []) for part in PARTS}


def find_hazards(floor: int, before: dict[str, int] | None,
                 after: dict[str, int]) -> list[tuple[str, str]]:
    """Compare today's counts with the last scan. Returns (text, OSHA topic) pairs."""
    if before is None:  # first scan of this floor: nothing to compare with
        return []
    hazards = []
    if after["openings"] > before["openings"]:
        hazards.append((f"New opening on Floor {floor}. Check guardrails.",
                        "Fall protection: holes and openings"))
    if after["doors"] < before["doors"]:
        hazards.append((f"A door is missing or blocked on Floor {floor}. Check exits.",
                        "Exit routes"))
    if after["walls"] < before["walls"]:
        hazards.append((f"A wall was removed on Floor {floor}. Check the structure.",
                        "Structural stability"))
    return hazards
