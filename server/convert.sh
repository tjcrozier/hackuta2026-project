#!/bin/sh
# Optional: convert a RoomPlan .usdz file to .glb with Blender (if Blender is installed).
# The server does NOT need this: it builds the .glb from the scan JSON (room_to_glb.py).
# Use this only if you want the exact RoomPlan model on the dashboard.
#
#   ./convert.sh scans/floor3-123.usdz scans/floor3-123.glb
set -e
if [ $# -ne 2 ]; then echo "usage: ./convert.sh in.usdz out.glb"; exit 1; fi
BLENDER=$(command -v blender || echo /Applications/Blender.app/Contents/MacOS/Blender)
if [ ! -x "$BLENDER" ]; then
  echo "Blender is not installed. Install it from blender.org, or keep the built-in .glb."
  exit 1
fi
"$BLENDER" -b -P "$(dirname "$0")/usd_to_glb.py" -- "$1" "$2"
