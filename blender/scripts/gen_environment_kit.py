"""Modular environment kit for Breachline maps.

Every piece is a function `piece_<name>(col) -> object` that builds the piece at the origin
(pieces sit on Z=0, wall pieces run along +X from the origin). `main()` exports every piece to
breachline/assets/models/environment/<name>.glb (with -convcol / -colonly collision and LOD1) and
saves blender/source/environment_kit.blend so pieces can be edited by hand.

The map generator (gen_map_foundry.py) imports these builders and instances them.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import bl_common as B  # noqa: E402


def palette():
    return {
        "concrete": B.mat("env_concrete", (0.52, 0.5, 0.47, 1), 0.9),
        "concrete_dark": B.mat("env_concrete_dark", (0.36, 0.35, 0.34, 1), 0.92),
        "brick": B.mat("env_brick", (0.45, 0.24, 0.18, 1), 0.85),
        "floor": B.mat("env_floor", (0.4, 0.39, 0.37, 1), 0.85),
        "floor_metal": B.mat("env_floor_metal", (0.3, 0.31, 0.33, 1), 0.55, 0.8),
        "steel": B.mat("env_steel", (0.35, 0.36, 0.38, 1), 0.5, 0.85),
        "rust": B.mat("env_rust", (0.42, 0.22, 0.12, 1), 0.8, 0.4),
        "wood": B.mat("env_wood", (0.5, 0.36, 0.2, 1), 0.8),
        "paint_yellow": B.mat("env_paint_yellow", (0.85, 0.65, 0.1, 1), 0.6),
        "paint_red": B.mat("env_paint_red", (0.6, 0.12, 0.1, 1), 0.6),
        "paint_blue": B.mat("env_paint_blue", (0.15, 0.3, 0.55, 1), 0.6),
        "glass": B.mat("env_glass", (0.5, 0.7, 0.8, 1), 0.1, 0.3),
        "sand": B.mat("env_sand", (0.55, 0.48, 0.32, 1), 0.95),
        "light": B.mat("env_light", (1.0, 0.95, 0.85, 1), 0.3, emission=(1.0, 0.95, 0.85, 1), emission_strength=6.0),
        "furnace_glow": B.mat("env_furnace_glow", (1.0, 0.4, 0.05, 1), 0.4, emission=(1.0, 0.35, 0.05, 1), emission_strength=8.0),
        "hazard": B.mat("env_hazard", (0.9, 0.75, 0.1, 1), 0.7),
    }


P = None  # set in main()/by importer via init_palette()


def init_palette():
    global P
    P = palette()
    return P


# ------------------------------------------------------------------ structural
def piece_wall(col, length=4.0, height=4.0, thickness=0.3, material=None, name="wall_4m"):
    return B.box(name, (length, thickness, height), (length / 2, 0, height / 2), material=material or P["concrete"], collection=col)


def piece_wall_low(col, length=4.0, name="wall_low"):
    return B.box(name, (length, 0.3, 1.1), (length / 2, 0, 0.55), material=P["concrete_dark"], collection=col)


def piece_wall_window(col, length=4.0, name="wall_window"):
    """Wall with a shoot-through window slot between 1.2 m and 2.2 m."""
    parts = [
        B.box("sill", (length, 0.3, 1.2), (length / 2, 0, 0.6), material=P["concrete"], collection=col),
        B.box("lintel", (length, 0.3, 1.8), (length / 2, 0, 3.1), material=P["concrete"], collection=col),
        B.box("post_a", (0.2, 0.3, 1.0), (0.1, 0, 1.7), material=P["concrete"], collection=col),
        B.box("post_b", (0.2, 0.3, 1.0), (length - 0.1, 0, 1.7), material=P["concrete"], collection=col),
        B.box("frame_lo", (length, 0.34, 0.06), (length / 2, 0, 1.2), material=P["steel"], collection=col),
        B.box("frame_hi", (length, 0.34, 0.06), (length / 2, 0, 2.2), material=P["steel"], collection=col),
    ]
    return B.join(parts, name)


def piece_door_frame(col, width=2.0, name="door_frame"):
    parts = [
        B.box("lintel", (width, 0.3, 1.6), (width / 2, 0, 3.2), material=P["concrete"], collection=col),
        B.box("jamb_a", (0.12, 0.34, 2.4), (0.06, 0, 1.2), material=P["steel"], collection=col),
        B.box("jamb_b", (0.12, 0.34, 2.4), (width - 0.06, 0, 1.2), material=P["steel"], collection=col),
        B.box("head", (width, 0.34, 0.12), (width / 2, 0, 2.46), material=P["steel"], collection=col),
    ]
    return B.join(parts, name)


def piece_door(col, name="door"):
    parts = [
        B.box("slab", (0.9, 0.06, 2.3), (0.45, 0, 1.15), material=P["paint_blue"], collection=col, bevel=0.01),
        B.box("panel", (0.6, 0.02, 0.8), (0.45, -0.04, 1.5), material=P["steel"], collection=col),
        B.cylinder("handle", 0.015, 0.12, (0.8, -0.06, 1.05), (0, 90, 0), P["steel"], col, 8),
    ]
    return B.join(parts, name)


def piece_floor(col, size=4.0, material=None, name="floor_4x4"):
    return B.box(name, (size, size, 0.2), (size / 2, size / 2, -0.1), material=material or P["floor"], collection=col)


def piece_pillar(col, name="pillar"):
    parts = [
        B.box("core", (0.6, 0.6, 4.0), (0, 0, 2.0), material=P["concrete_dark"], collection=col),
        B.box("base", (0.8, 0.8, 0.3), (0, 0, 0.15), material=P["concrete"], collection=col),
        B.box("stripe", (0.62, 0.62, 0.3), (0, 0, 1.0), material=P["hazard"], collection=col),
    ]
    return B.join(parts, name)


def piece_stairs(col, length=2.0, rise=1.0, width=2.0, name="stairs_2m"):
    """Steps rising `rise` over `length` along +X, plus an invisible ramp collision (-colonly)."""
    steps = max(2, int(rise / 0.2))
    parts = []
    for i in range(steps):
        h = rise * (i + 1) / steps
        x0 = length * i / steps
        parts.append(B.box(f"step{i}", (length / steps, width, h), (x0 + length / steps / 2, width / 2, h / 2), material=P["floor_metal"], collection=col))
    obj = B.join(parts, name)
    # smooth ramp collision so players slide up
    bm_verts = [(0, 0, 0), (length, 0, rise), (length, width, rise), (0, width, 0),
                (0, 0, -0.2), (length, 0, rise - 0.2), (length, width, rise - 0.2), (0, width, -0.2)]
    ramp = _prism(name + "-colonly", bm_verts, col)
    ramp.parent = obj
    return obj


def _prism(name, verts, col):
    import bmesh
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.display_type = "WIRE"
    col.objects.link(ob)
    return ob


def piece_catwalk(col, length=4.0, width=2.0, name="catwalk_4m"):
    parts = [
        B.box("deck", (length, width, 0.1), (length / 2, width / 2, 2.95), material=P["floor_metal"], collection=col),
        B.box("beam_a", (length, 0.15, 0.3), (length / 2, 0.075, 2.75), material=P["rust"], collection=col),
        B.box("beam_b", (length, 0.15, 0.3), (length / 2, width - 0.075, 2.75), material=P["rust"], collection=col),
    ]
    return B.join(parts, name)


def piece_railing(col, length=2.0, name="railing_2m"):
    parts = [B.box("top", (length, 0.05, 0.05), (length / 2, 0, 1.05), material=P["hazard"], collection=col),
             B.box("mid", (length, 0.03, 0.03), (length / 2, 0, 0.55), material=P["steel"], collection=col)]
    n = max(2, int(length / 1.0) + 1)
    for i in range(n):
        parts.append(B.box(f"post{i}", (0.05, 0.05, 1.05), (i * length / (n - 1), 0, 0.525), material=P["steel"], collection=col))
    return B.join(parts, name)


def piece_ladder(col, height=3.0, name="ladder_3m"):
    parts = [B.box("rail_a", (0.05, 0.05, height), (-0.25, 0, height / 2), material=P["steel"], collection=col),
             B.box("rail_b", (0.05, 0.05, height), (0.25, 0, height / 2), material=P["steel"], collection=col)]
    for i in range(int(height / 0.3)):
        parts.append(B.cylinder(f"rung{i}", 0.02, 0.5, (0, 0, 0.3 * (i + 1)), (0, 90, 0), P["steel"], col, 6))
    return B.join(parts, name)


# ------------------------------------------------------------------ props
def piece_crate(col, size=1.6, name="crate"):
    parts = [B.box("body", (size, size, size), (0, 0, size / 2), material=P["wood"], collection=col, bevel=0.02)]
    for z in (0.1, size - 0.1):
        parts.append(B.box("band", (size + 0.02, size + 0.02, 0.08), (0, 0, z), material=P["steel"], collection=col))
    for a in (0, 90):
        parts.append(B.box("brace", (size + 0.03, 0.08, size * 0.7), (0, 0, size / 2), (0, 0, a), P["wood"], col))
    return B.join(parts, name)


def piece_crate_tall(col, name="crate_tall"):
    a = piece_crate(col, 1.6, "lower")
    b = piece_crate(col, 1.4, "upper")
    b.location = (0.05, -0.05, 1.6)
    return B.join([a, b], name)


def piece_barrier(col, name="barrier"):
    """Jersey-style concrete barrier, 2 m long, 1.1 m tall."""
    verts = [(-1, -0.35, 0), (1, -0.35, 0), (1, 0.35, 0), (-1, 0.35, 0),
             (-1, -0.15, 1.1), (1, -0.15, 1.1), (1, 0.15, 1.1), (-1, 0.15, 1.1)]
    ob = _prism("barrier_body", verts, col)
    ob.display_type = "TEXTURED"
    ob.data.materials.append(P["concrete_dark"])
    stripe = B.box("stripe", (0.5, 0.72, 0.4), (0.5, 0, 0.5), material=P["hazard"], collection=col)
    return B.join([ob, stripe], name)


def piece_barrel(col, name="barrel"):
    parts = [B.cylinder("body", 0.3, 0.9, (0, 0, 0.45), (0, 0, 0), P["paint_blue"], col, 14)]
    for z in (0.25, 0.65):
        parts.append(B.cylinder(f"rim{z}", 0.31, 0.04, (0, 0, z), (0, 0, 0), P["steel"], col, 14))
    parts.append(B.cylinder("lid", 0.29, 0.03, (0, 0, 0.9), (0, 0, 0), P["steel"], col, 14))
    return B.join(parts, name)


def piece_sandbag(col, name="sandbag"):
    parts = []
    for row, z in ((3, 0.15), (2, 0.42), (1, 0.68)):
        for i in range(row):
            parts.append(B.box(f"bag{row}{i}", (0.55, 0.9, 0.28), (-(row - 1) * 0.28 + i * 0.56, 0, z), material=P["sand"], collection=col, bevel=0.06))
    return B.join(parts, name)


def piece_pipe(col, length=4.0, radius=0.2, name="pipe_4m"):
    parts = [B.cylinder("pipe", radius, length, (length / 2, 0, 0), (0, 90, 0), P["rust"], col, 10)]
    for x in (0.3, length - 0.3):
        parts.append(B.cylinder(f"flange{x}", radius * 1.3, 0.1, (x, 0, 0), (0, 90, 0), P["steel"], col, 10))
    return B.join(parts, name)


def piece_pipe_corner(col, radius=0.2, name="pipe_corner"):
    parts = [B.cylinder("a", radius, 1.0, (0.5, 0, 0), (0, 90, 0), P["rust"], col, 10),
             B.cylinder("b", radius, 1.0, (0, 0, 0.5), (0, 0, 0), P["rust"], col, 10),
             B.sphere("elbow", radius, (0, 0, 0), P["rust"], col, 10, 6)]
    return B.join(parts, name)


def piece_light(col, name="light_fixture"):
    parts = [B.box("housing", (1.2, 0.3, 0.1), (0, 0, 0.05), material=P["steel"], collection=col),
             B.box("tube", (1.1, 0.2, 0.04), (0, 0, -0.02), material=P["light"], collection=col),
             B.box("chain", (0.03, 0.03, 0.6), (0, 0, 0.4), material=P["steel"], collection=col)]
    return B.join(parts, name)


def piece_generator(col, name="generator"):
    parts = [B.box("body", (2.4, 1.2, 1.4), (0, 0, 0.7), material=P["paint_yellow"], collection=col, bevel=0.03),
             B.box("panel", (0.6, 0.05, 0.5), (0.6, -0.62, 0.9), material=P["steel"], collection=col),
             B.cylinder("exhaust", 0.08, 0.6, (-0.9, 0, 1.6), (0, 0, 0), P["rust"], col, 8),
             B.box("grille", (0.9, 0.05, 0.8), (-0.5, -0.62, 0.7), material=P["concrete_dark"], collection=col)]
    return B.join(parts, name)


def piece_furnace(col, name="furnace"):
    parts = [B.box("body", (6.0, 3.0, 4.5), (0, 0, 2.25), material=P["brick"], collection=col, bevel=0.05),
             B.box("mouth", (2.2, 0.4, 1.6), (0, -1.5, 1.4), material=P["furnace_glow"], collection=col),
             B.box("hood", (3.0, 1.2, 0.8), (0, -1.6, 2.9), material=P["steel"], collection=col),
             B.cylinder("stack", 0.6, 3.0, (1.8, 0.5, 6.0), (0, 0, 0), P["rust"], col, 12),
             B.box("ledge", (6.4, 3.4, 0.3), (0, 0, 4.6), material=P["concrete_dark"], collection=col)]
    for i in range(3):
        parts.append(B.box(f"pipe{i}", (0.2, 0.2, 4.0), (-2.4 + i * 0.4, 1.4, 2.0), material=P["rust"], collection=col))
    return B.join(parts, name)


def piece_silo(col, name="silo"):
    parts = [B.cylinder("body", 2.2, 8.0, (0, 0, 4.0), (0, 0, 0), P["steel"], col, 20),
             B.cylinder("cone", 2.2, 1.5, (0, 0, 8.75), (0, 0, 0), P["rust"], col, 20, radius2=0.5),
             B.box("hatch", (0.8, 0.1, 1.2), (0, -2.2, 1.0), material=P["paint_red"], collection=col)]
    for i in range(4):
        parts.append(B.box(f"leg{i}", (0.25, 0.25, 1.2), (math.cos(i * math.pi / 2) * 1.9, math.sin(i * math.pi / 2) * 1.9, 0.6), material=P["rust"], collection=col))
    for z in (2.0, 4.5, 7.0):
        parts.append(B.cylinder(f"band{z}", 2.25, 0.15, (0, 0, z), (0, 0, 0), P["paint_yellow"], col, 20))
    return B.join(parts, name)


def piece_conveyor(col, length=6.0, name="conveyor_6m"):
    parts = [B.box("belt", (length, 1.0, 0.1), (length / 2, 0, 0.9), material=P["concrete_dark"], collection=col),
             B.box("frame", (length, 1.1, 0.2), (length / 2, 0, 0.75), material=P["rust"], collection=col)]
    for x in (0.4, length - 0.4):
        parts.append(B.box(f"leg{x}", (0.15, 1.0, 0.7), (x, 0, 0.35), material=P["steel"], collection=col))
        parts.append(B.cylinder(f"roller{x}", 0.15, 1.0, (x, 0, 0.9), (90, 0, 0), P["steel"], col, 10))
    return B.join(parts, name)


def piece_control_console(col, name="control_console"):
    parts = [B.box("desk", (2.4, 0.8, 0.9), (0, 0, 0.45), material=P["steel"], collection=col, bevel=0.02),
             B.box("panel", (2.3, 0.5, 0.3), (0, -0.1, 1.0), (30, 0, 0), P["concrete_dark"], col),
             B.box("screen", (0.8, 0.05, 0.5), (-0.6, 0.3, 1.3), material=P["glass"], collection=col),
             B.box("screen2", (0.8, 0.05, 0.5), (0.6, 0.3, 1.3), material=P["glass"], collection=col)]
    return B.join(parts, name)


def piece_lamp_post(col, name="lamp_post"):
    parts = [B.cylinder("pole", 0.06, 4.0, (0, 0, 2.0), (0, 0, 0), P["steel"], col, 8),
             B.box("head", (0.5, 0.3, 0.15), (0.2, 0, 4.0), material=P["steel"], collection=col),
             B.box("bulb", (0.4, 0.2, 0.05), (0.2, 0, 3.9), material=P["light"], collection=col)]
    return B.join(parts, name)


def piece_vent(col, name="vent"):
    parts = [B.box("duct", (1.0, 1.0, 1.0), (0, 0, 0.5), material=P["steel"], collection=col, bevel=0.03),
             B.cylinder("fan", 0.4, 0.1, (0, 0, 1.0), (0, 0, 0), P["concrete_dark"], col, 12)]
    return B.join(parts, name)


KIT = {
    "wall_4m": lambda c: piece_wall(c), "wall_2m": lambda c: piece_wall(c, 2.0, name="wall_2m"),
    "wall_low": piece_wall_low, "wall_window": piece_wall_window, "door_frame": piece_door_frame, "door": piece_door,
    "floor_4x4": piece_floor, "floor_2x2": lambda c: piece_floor(c, 2.0, name="floor_2x2"), "pillar": piece_pillar,
    "stairs_2m": piece_stairs, "catwalk_4m": piece_catwalk, "railing_2m": piece_railing, "ladder_3m": piece_ladder,
    "crate": piece_crate, "crate_tall": piece_crate_tall, "barrier": piece_barrier, "barrel": piece_barrel,
    "sandbag": piece_sandbag, "pipe_4m": piece_pipe, "pipe_corner": piece_pipe_corner, "light_fixture": piece_light,
    "generator": piece_generator, "furnace": piece_furnace, "silo": piece_silo, "conveyor_6m": piece_conveyor,
    "control_console": piece_control_console, "lamp_post": piece_lamp_post, "vent": piece_vent,
}


def main():
    B.reset_scene()
    init_palette()
    out = os.path.join(B.GODOT_MODELS, "environment")
    x = 0.0
    for name, builder in KIT.items():
        col = B.ensure_collection(f"kit_{name}")
        obj = builder(col)
        B.box_uv(obj, 1.0)
        B.apply_transforms(obj)
        if name not in ("floor_4x4", "floor_2x2", "wall_4m", "wall_2m", "wall_low", "catwalk_4m"):
            B.make_lod(obj, 0.5, 1).parent = obj
        if not any(ch.name.endswith("-colonly") for ch in obj.children):
            (B.make_box_collision if name in ("crate", "crate_tall", "generator", "control_console", "vent") else B.make_convex_collision)(obj).parent = obj
        B.export_glb(os.path.join(out, f"{name}.glb"), B.collection_objects(col), animations=False)
        # spread pieces out in the .blend for browsing
        obj.location.x = x
        x += 8.0
    B.validate_scene()
    B.save_blend("environment_kit.blend")


if __name__ == "__main__":
    main()
