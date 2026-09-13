"""Regenerate and export every Breachline asset.

    python blender/scripts/export_all.py            # with the `bpy` pip module
    blender --background --python blender/scripts/export_all.py

Runs, in order: weapons -> characters -> environment kit -> map. Each generator validates naming,
applies transforms, builds LOD/collision meshes, exports GLB into breachline/assets/models and
saves an editable .blend into blender/source.
"""
import importlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))

GENERATORS = ["gen_weapons", "gen_characters", "gen_environment_kit", "gen_map_foundry"]


def main(only=None):
    t0 = time.time()
    for name in GENERATORS:
        if only and name not in only:
            continue
        print(f"\n=== {name} ===")
        mod = importlib.import_module(name)
        mod.main()
    print(f"\nAll assets exported in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a.startswith("gen_")]
    main(args or None)
