"""Early-development helper: regenerate a single asset category quickly.

    python blender/scripts/regen_placeholders.py weapons|characters|environment|map

The real generators are already procedural, so "placeholders" and final assets share one code
path; this script just narrows the batch to one category for fast iteration.
"""
import sys
import export_all

CATS = {"weapons": "gen_weapons", "characters": "gen_characters", "environment": "gen_environment_kit", "map": "gen_map_foundry"}
if __name__ == "__main__":
    cats = [CATS[a] for a in sys.argv[1:] if a in CATS] or list(CATS.values())
    export_all.main(cats)
