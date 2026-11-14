"""Run inside Blender: blender -b -P usd_to_glb.py -- in.usdz out.glb (see convert.sh)."""

import sys

import bpy  # only exists inside Blender

source, target = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=source)
bpy.ops.export_scene.gltf(filepath=target, export_format="GLB")
