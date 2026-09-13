"""Validate naming conventions of the currently open .blend (or a file passed as argument).

    blender --background blender/source/weapons.blend --python blender/scripts/validate_names.py
    python blender/scripts/validate_names.py blender/source/weapons.blend
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
import bl_common as B  # noqa: E402

if __name__ == "__main__":
    files = [a for a in sys.argv[1:] if a.endswith(".blend")]
    if files:
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(files[0]))
    problems = B.validate_scene(strict=False)
    if problems:
        print("PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
    print(f"OK: {len(bpy.data.objects)} objects pass naming/transform validation")
