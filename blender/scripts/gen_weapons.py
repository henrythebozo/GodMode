"""Generate every Breachline firearm, melee weapon, grenade and objective item.

Each weapon is a parametric low-poly hard-surface model built from bevelled primitives and
joined into a single mesh, with a convex collision mesh (for dropped-weapon physics), a LOD1
mesh and marker empties (muzzle / eject / mag_socket / grip_r / grip_l / sight).

Weapons are drawn along -Y and mirrored to +Y-forward (Godot -Z) at the end, with the grip near
the origin so the same GLB works as a first-person view model and a third-person pickup mesh.

Run:  python blender/scripts/gen_weapons.py      (bpy module)
      blender --background --python blender/scripts/gen_weapons.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bl_common as B  # noqa: E402

# ---------------------------------------------------------------------------------- palette
def palette():
    return {
        "steel": B.mat("gun_steel", (0.22, 0.23, 0.25, 1), roughness=0.45, metallic=0.85),
        "dark": B.mat("gun_polymer", (0.08, 0.08, 0.09, 1), roughness=0.75),
        "grip": B.mat("gun_grip", (0.12, 0.10, 0.09, 1), roughness=0.9),
        "wood": B.mat("gun_wood", (0.32, 0.18, 0.09, 1), roughness=0.7),
        "brass": B.mat("gun_brass", (0.75, 0.6, 0.25, 1), roughness=0.35, metallic=0.9),
        "accent": B.mat("gun_accent", (0.75, 0.35, 0.08, 1), roughness=0.5, metallic=0.3),
        "glass": B.mat("gun_glass", (0.2, 0.6, 0.9, 1), roughness=0.1, metallic=0.2,
                        emission=(0.2, 0.6, 0.9, 1), emission_strength=0.6),
        "olive": B.mat("nade_olive", (0.25, 0.3, 0.16, 1), roughness=0.8),
        "grey": B.mat("nade_grey", (0.45, 0.47, 0.5, 1), roughness=0.6, metallic=0.4),
        "red": B.mat("nade_red", (0.65, 0.12, 0.08, 1), roughness=0.55),
        "white": B.mat("nade_white", (0.85, 0.85, 0.82, 1), roughness=0.6),
        "yellow": B.mat("nade_yellow", (0.9, 0.7, 0.1, 1), roughness=0.5),
        "led": B.mat("bomb_led", (1.0, 0.1, 0.1, 1), roughness=0.3, emission=(1.0, 0.1, 0.1, 1), emission_strength=4.0),
        "screen": B.mat("bomb_screen", (0.1, 0.9, 0.3, 1), roughness=0.2, emission=(0.1, 0.9, 0.3, 1), emission_strength=2.0),
    }


# Parametric description of every firearm. Sizes in metres.
# barrel_len is measured from the receiver front. All weapons: forward = -Y.
FIREARMS = {
    # id: (category, receiver(len,w,h), barrel_len, barrel_r, mag(len,w,h), stock kind, extras)
    "p9":       ("pistol", (0.17, 0.03, 0.035), 0.03, 0.007, (0.02, 0.026, 0.09), None, ["slide"]),
    "kestrel":  ("pistol", (0.19, 0.032, 0.038), 0.035, 0.008, (0.022, 0.028, 0.095), None, ["slide", "rail"]),
    "hornet":   ("pistol", (0.18, 0.032, 0.04), 0.02, 0.007, (0.024, 0.03, 0.13), None, ["slide", "foldstock"]),
    "warden":   ("pistol", (0.20, 0.034, 0.045), 0.10, 0.011, (0.0, 0.0, 0.0), None, ["cylinder"]),
    "viper":    ("smg", (0.30, 0.05, 0.07), 0.14, 0.012, (0.03, 0.028, 0.16), "collapsible", ["rail", "foregrip"]),
    "reed":     ("smg", (0.26, 0.05, 0.075), 0.10, 0.011, (0.03, 0.026, 0.14), "folding", ["rail"]),
    "bulldog":  ("smg", (0.28, 0.055, 0.075), 0.12, 0.012, (0.032, 0.03, 0.15), "fixed", ["rail", "foregrip"]),
    "breaker":  ("shotgun", (0.32, 0.05, 0.07), 0.42, 0.014, (0.0, 0.0, 0.0), "fixed", ["tube", "pump"]),
    "salvo":    ("shotgun", (0.34, 0.055, 0.08), 0.36, 0.014, (0.05, 0.035, 0.12), "fixed", ["rail", "drum"]),
    "corsair":  ("rifle", (0.34, 0.055, 0.08), 0.32, 0.011, (0.035, 0.03, 0.19), "fixed", ["rail", "handguard", "carry"]),
    "lynx":     ("rifle", (0.32, 0.055, 0.08), 0.30, 0.011, (0.035, 0.03, 0.18), "collapsible", ["rail", "handguard"]),
    "falcon":   ("rifle", (0.36, 0.06, 0.09), 0.26, 0.011, (0.035, 0.03, 0.18), "fixed", ["rail", "handguard", "scope"]),
    "raptor":   ("rifle", (0.40, 0.06, 0.09), 0.40, 0.012, (0.04, 0.032, 0.16), "fixed", ["rail", "handguard", "scope", "bipod"]),
    "longbow":  ("sniper", (0.42, 0.06, 0.09), 0.62, 0.013, (0.03, 0.03, 0.10), "fixed", ["bolt", "scope", "bipod"]),
    "marksman": ("sniper", (0.44, 0.06, 0.09), 0.50, 0.012, (0.035, 0.032, 0.15), "fixed", ["rail", "scope", "handguard"]),
    "anvil":    ("lmg", (0.46, 0.07, 0.10), 0.48, 0.014, (0.14, 0.09, 0.12), "fixed", ["rail", "handguard", "bipod", "box"]),
}


def build_firearm(wid, spec, P, col):
    category, (rl, rw, rh), bl, br, (ml, mw, mh), stock, extras = spec
    parts = []
    bev = 0.003
    # receiver: centred so the pistol grip sits at the origin
    rec_y = -rl * 0.5 + 0.06
    parts.append(B.box("receiver", (rw, rl, rh), (0, rec_y, rh * 0.5 + 0.03), material=P["steel"], collection=col, bevel=bev))
    front = rec_y - rl * 0.5
    # barrel
    if bl > 0:
        parts.append(B.cylinder("barrel", br, bl, (0, front - bl * 0.5, rh * 0.5 + 0.045), (90, 0, 0), P["dark"], col, 10))
        parts.append(B.cylinder("muzzle_ring", br * 1.4, 0.02, (0, front - bl + 0.01, rh * 0.5 + 0.045), (90, 0, 0), P["steel"], col, 10))
    # handguard around the rear half of the barrel
    if "handguard" in extras:
        hl = min(bl * 0.6, 0.22)
        parts.append(B.box("handguard", (rw * 0.9, hl, rh * 0.75), (0, front - hl * 0.5, rh * 0.5 + 0.04), material=P["dark"], collection=col, bevel=bev))
    if "tube" in extras:
        parts.append(B.cylinder("mag_tube", br * 1.1, bl * 0.85, (0, front - bl * 0.42, rh * 0.5 + 0.015), (90, 0, 0), P["steel"], col, 10))
    if "pump" in extras:
        parts.append(B.cylinder("pump", br * 2.3, 0.11, (0, front - bl * 0.45, rh * 0.5 + 0.015), (90, 0, 0), P["grip"], col, 10))
    if "foregrip" in extras:
        parts.append(B.box("foregrip", (0.025, 0.03, 0.06), (0, front - bl * 0.35, rh * 0.5 - 0.02), material=P["grip"], collection=col, bevel=bev))
    # pistol grip at origin (angled back)
    grip_h = 0.085 if category != "pistol" else 0.075
    parts.append(B.box("grip", (0.028, 0.04, grip_h), (0, 0.015, grip_h * 0.5 - 0.045), (18, 0, 0), P["grip"], col, bev))
    # trigger guard
    parts.append(B.box("trigger_guard", (0.02, 0.05, 0.006), (0, -0.02, 0.028), material=P["steel"], collection=col))
    parts.append(B.box("trigger", (0.006, 0.006, 0.02), (0, -0.02, 0.04), material=P["steel"], collection=col))
    # magazine
    if ml > 0:
        if "box" in extras:
            parts.append(B.box("ammo_box", (mw, ml, mh), (rw * 0.5 + mw * 0.5, rec_y - 0.02, 0.0), material=P["olive"], collection=col, bevel=bev))
        elif "drum" in extras:
            parts.append(B.cylinder("drum", 0.06, 0.05, (0, rec_y - 0.05, -0.02), (0, 90, 0), P["dark"], col, 14))
        else:
            parts.append(B.box("magazine", (mw, ml, mh), (0, rec_y - 0.03, -mh * 0.5 + 0.03), (-6, 0, 0), P["dark"], col, bev))
    if "cylinder" in extras:
        parts.append(B.cylinder("revolver_cyl", 0.02, 0.045, (0, rec_y - 0.02, rh * 0.5 + 0.03), (90, 0, 0), P["steel"], col, 8))
    if "slide" in extras:
        parts.append(B.box("slide", (rw * 0.9, rl * 0.95, rh * 0.5), (0, rec_y, rh + 0.03), material=P["dark"], collection=col, bevel=bev))
    # stock
    rear = rec_y + rl * 0.5
    if stock == "fixed":
        parts.append(B.box("stock", (rw * 0.8, 0.22, rh * 0.8), (0, rear + 0.11, rh * 0.5 + 0.02), material=P["dark"], collection=col, bevel=bev))
        parts.append(B.box("buttpad", (rw * 0.85, 0.02, rh * 1.1), (0, rear + 0.23, rh * 0.5 + 0.015), material=P["grip"], collection=col))
    elif stock == "collapsible":
        parts.append(B.cylinder("buffer_tube", 0.014, 0.18, (0, rear + 0.09, rh * 0.5 + 0.045), (90, 0, 0), P["steel"], col, 8))
        parts.append(B.box("stock", (rw * 0.9, 0.09, rh * 0.9), (0, rear + 0.16, rh * 0.5 + 0.02), material=P["dark"], collection=col, bevel=bev))
    elif stock == "folding":
        parts.append(B.box("stock_bar", (0.01, 0.2, 0.01), (rw * 0.4, rear + 0.1, rh * 0.5 + 0.05), material=P["steel"], collection=col))
        parts.append(B.box("stock_bar2", (0.01, 0.2, 0.01), (-rw * 0.4, rear + 0.1, rh * 0.5 + 0.05), material=P["steel"], collection=col))
        parts.append(B.box("buttpad", (rw, 0.02, 0.05), (0, rear + 0.2, rh * 0.5 + 0.04), material=P["grip"], collection=col))
    if "foldstock" in extras:
        parts.append(B.box("foldstock", (0.01, 0.12, 0.012), (-rw * 0.5, rear + 0.06, 0.05), material=P["steel"], collection=col))
    # sights / rail / scope
    top = rh + 0.03 + (rh * 0.5 if "slide" in extras else 0)
    if "rail" in extras:
        parts.append(B.box("rail", (0.02, rl * 0.8, 0.008), (0, rec_y, top + 0.004), material=P["steel"], collection=col))
        top += 0.008
    if "scope" in extras:
        parts.append(B.cylinder("scope", 0.016, 0.16, (0, rec_y - 0.02, top + 0.03), (90, 0, 0), P["dark"], col, 12))
        parts.append(B.cylinder("scope_lens", 0.014, 0.004, (0, rec_y - 0.1, top + 0.03), (90, 0, 0), P["glass"], col, 12))
        parts.append(B.box("scope_mount", (0.02, 0.04, 0.02), (0, rec_y, top + 0.012), material=P["steel"], collection=col))
    else:
        parts.append(B.box("rear_sight", (0.02, 0.008, 0.012), (0, rec_y + rl * 0.4, top + 0.006), material=P["steel"], collection=col))
        parts.append(B.box("front_sight", (0.004, 0.006, 0.014), (0, front + 0.01 if bl < 0.05 else front - bl + 0.03, top + 0.007), material=P["steel"], collection=col))
    if "carry" in extras:
        parts.append(B.box("carry_handle", (0.016, 0.1, 0.02), (0, rec_y + 0.02, top + 0.02), material=P["steel"], collection=col))
    if "bolt" in extras:
        parts.append(B.cylinder("bolt_handle", 0.005, 0.05, (-rw * 0.5 - 0.02, rec_y + 0.05, rh * 0.5 + 0.045), (0, 90, 0), P["steel"], col, 8))
        parts.append(B.sphere("bolt_knob", 0.009, (-rw * 0.5 - 0.045, rec_y + 0.05, rh * 0.5 + 0.045), P["steel"], col, 8, 6))
    if "bipod" in extras:
        for sx in (-1, 1):
            parts.append(B.box("bipod_leg", (0.008, 0.008, 0.12), (sx * 0.03, front - bl * 0.75, rh * 0.5 - 0.02), (0, sx * 15, 0), P["steel"], col))
    # charging handle / ejection port detail
    parts.append(B.box("eject_port", (0.004, 0.03, 0.014), (-rw * 0.5, rec_y - 0.02, rh * 0.5 + 0.04), material=P["dark"], collection=col))
    accent = B.box("accent_plate", (rw * 1.02, 0.03, rh * 0.3), (0, rec_y + rl * 0.25, rh * 0.5 + 0.05), material=P["accent"], collection=col)
    parts.append(accent)

    body = B.join(parts, f"wpn_{wid}")
    pfx = wid
    B.box_uv(body, 0.25)
    B.shade_smooth(body, 40)
    B.apply_transforms(body)
    # markers (parented to the mesh so they travel with it in Godot)
    muzzle_y = front - bl if bl > 0 else front
    B.empty("muzzle", (0, muzzle_y - 0.005, rh * 0.5 + 0.045), (90, 0, 0), body, col, prefix=pfx)
    B.empty("eject", (-rw * 0.5 - 0.01, rec_y - 0.02, rh * 0.5 + 0.045), (0, -60, 0), body, col, prefix=pfx)
    B.empty("mag_socket", (0, rec_y - 0.03, 0.0), (0, 0, 0), body, col, prefix=pfx)
    B.empty("grip_r", (0, 0.03, -0.01), (0, 0, 0), body, col, prefix=pfx)
    B.empty("grip_l", (0, front - max(bl * 0.35, 0.02), 0.0), (0, 0, 0), body, col, prefix=pfx)
    B.empty("sight", (0, rec_y, top + 0.02), (0, 0, 0), body, col, prefix=pfx)
    B.empty("attach_top", (0, rec_y, top), (0, 0, 0), body, col, prefix=pfx)
    # LOD + collision
    lod = B.make_lod(body, 0.45, 1)
    lod.parent = body
    lod.matrix_world = body.matrix_world
    coll = B.make_convex_collision(body)
    coll.parent = body
    B.mirror_forward(body)
    body["category"] = category
    body["weapon_id"] = wid
    return body


def build_knife(P, col):
    parts = [
        B.box("blade", (0.004, 0.16, 0.03), (0, -0.10, 0.0), material=P["steel"], collection=col, bevel=0.002),
        B.box("blade_tip", (0.004, 0.05, 0.015), (0, -0.20, 0.007), (0, 0, 0), P["steel"], col),
        B.box("guard", (0.02, 0.01, 0.045), (0, -0.02, 0), material=P["brass"], collection=col),
        B.cylinder("handle", 0.012, 0.11, (0, 0.04, 0), (90, 0, 0), P["grip"], col, 8),
        B.sphere("pommel", 0.013, (0, 0.1, 0), P["brass"], col, 8, 6),
    ]
    body = B.join(parts, "wpn_knife")
    pfx = "knife"
    B.box_uv(body, 0.1)
    B.apply_transforms(body)
    B.empty("grip_r", (0, 0.04, 0), (0, 0, 0), body, col, prefix=pfx)
    coll = B.make_convex_collision(body)
    coll.parent = body
    B.mirror_forward(body)
    body["category"] = "melee"
    body["weapon_id"] = "knife"
    return body


def build_grenade(gid, P, col):
    kind = {"frag": ("olive", "sphere"), "flash": ("grey", "can"), "smoke": ("white", "can"),
            "incendiary": ("red", "bottle"), "decoy": ("yellow", "sphere")}[gid]
    color, shape = kind
    parts = []
    if shape == "sphere":
        parts.append(B.sphere("body", 0.035, (0, 0, 0), P[color], col, 12, 8))
        for z in (-0.015, 0.0, 0.015):
            parts.append(B.cylinder("groove", 0.036, 0.004, (0, 0, z), (0, 0, 0), P["dark"], col, 12))
    elif shape == "can":
        parts.append(B.cylinder("body", 0.028, 0.10, (0, 0, 0), (0, 0, 0), P[color], col, 12))
        parts.append(B.cylinder("cap", 0.029, 0.012, (0, 0, 0.05), (0, 0, 0), P["steel"], col, 12))
        parts.append(B.box("label", (0.059, 0.059, 0.03), (0, 0, -0.01), material=P["accent"], collection=col))
    else:
        parts.append(B.cylinder("body", 0.032, 0.11, (0, 0, -0.01), (0, 0, 0), P["glass"], col, 12))
        parts.append(B.cylinder("neck", 0.014, 0.05, (0, 0, 0.07), (0, 0, 0), P["glass"], col, 10))
        parts.append(B.box("rag", (0.02, 0.02, 0.05), (0, 0, 0.1), material=P["white"], collection=col))
        parts.append(B.box("tape", (0.066, 0.066, 0.02), (0, 0, -0.02), material=P["red"], collection=col))
    # fuse head + spoon (lever)
    parts.append(B.cylinder("fuse", 0.012, 0.02, (0, 0, 0.045 if shape == "sphere" else 0.062), (0, 0, 0), P["steel"], col, 8))
    parts.append(B.box("spoon", (0.01, 0.006, 0.06), (0.012, 0, 0.03), (0, -12, 0), P["steel"], col))
    parts.append(B.cylinder("pin_ring", 0.01, 0.002, (-0.014, 0, 0.055), (0, 90, 0), P["brass"], col, 10))
    body = B.join(parts, f"nade_{gid}")
    pfx = gid
    B.box_uv(body, 0.1)
    B.shade_smooth(body, 40)
    B.apply_transforms(body)
    B.empty("grip_r", (0, 0, -0.01), (0, 0, 0), body, col, prefix=pfx)
    B.empty("pin", (-0.014, 0, 0.055), (0, 0, 0), body, col, prefix=pfx)
    coll = B.make_convex_collision(body)
    coll.parent = body
    B.mirror_forward(body)
    body["category"] = "grenade"
    body["weapon_id"] = gid
    return body


def build_bomb(P, col):
    parts = [
        B.box("case", (0.28, 0.18, 0.09), (0, 0, 0.045), material=P["dark"], collection=col, bevel=0.006),
        B.box("lid", (0.26, 0.16, 0.01), (0, 0, 0.095), material=P["steel"], collection=col, bevel=0.002),
        B.box("screen", (0.10, 0.05, 0.004), (-0.05, 0.03, 0.102), material=P["screen"], collection=col),
        B.cylinder("led", 0.008, 0.006, (0.08, 0.04, 0.103), (0, 0, 0), P["led"], col, 8),
        B.box("keypad", (0.08, 0.06, 0.006), (0.06, -0.03, 0.103), material=P["grey"], collection=col),
        B.box("handle", (0.10, 0.02, 0.02), (0, 0.10, 0.06), material=P["grip"], collection=col, bevel=0.003),
    ]
    for i in range(4):
        parts.append(B.cylinder("charge", 0.03, 0.15, (-0.09 + i * 0.06, 0, 0.045), (90, 0, 0), P["red"], col, 8))
    for i in range(3):
        parts.append(B.box("wire", (0.003, 0.12, 0.003), (-0.1 + i * 0.01, 0, 0.1 + i * 0.004), material=P["yellow" if i == 1 else "red"], collection=col))
    body = B.join(parts, "obj_bomb")
    pfx = "bomb"
    B.box_uv(body, 0.2)
    B.apply_transforms(body)
    B.empty("grip_r", (0, 0.1, 0.06), (0, 0, 0), body, col, prefix=pfx)
    B.empty("origin_fp", (0, 0, 0.05), (0, 0, 0), body, col, prefix=pfx)
    coll = B.make_box_collision(body, colonly=True)
    coll.parent = body
    B.mirror_forward(body)
    body["category"] = "objective"
    body["weapon_id"] = "bomb"
    return body


def build_defuse_kit(P, col):
    parts = [
        B.box("pouch", (0.14, 0.06, 0.10), (0, 0, 0.05), material=P["olive"], collection=col, bevel=0.005),
        B.box("flap", (0.14, 0.02, 0.05), (0, -0.03, 0.08), material=P["grip"], collection=col, bevel=0.003),
        B.cylinder("cutters", 0.006, 0.12, (0.03, -0.02, 0.08), (20, 0, 0), P["steel"], col, 8),
        B.box("clip", (0.04, 0.01, 0.03), (0, 0.035, 0.09), material=P["steel"], collection=col),
    ]
    body = B.join(parts, "obj_defuse_kit")
    B.box_uv(body, 0.1)
    B.apply_transforms(body)
    coll = B.make_box_collision(body, colonly=True)
    coll.parent = body
    body["category"] = "objective"
    body["weapon_id"] = "defuse_kit"
    return body


def build_shell_casing(P, col):
    body = B.cylinder("fx_shell_casing", 0.004, 0.02, (0, 0, 0), (0, 0, 0), P["brass"], col, 8)
    B.box_uv(body, 0.02)
    B.apply_transforms(body)
    return body


def main():
    B.reset_scene()
    P = palette()
    out_dir = os.path.join(B.GODOT_MODELS, "weapons")
    for wid, spec in FIREARMS.items():
        col = B.ensure_collection(f"weapon_{wid}")
        obj = build_firearm(wid, spec, P, col)
        B.validate_scene()
        B.export_glb(os.path.join(out_dir, f"{wid}.glb"), B.collection_objects(col), animations=False)
    col = B.ensure_collection("weapon_knife")
    build_knife(P, col)
    B.export_glb(os.path.join(out_dir, "knife.glb"), B.collection_objects(col), animations=False)
    for gid in ("frag", "flash", "smoke", "incendiary", "decoy"):
        col = B.ensure_collection(f"grenade_{gid}")
        build_grenade(gid, P, col)
        B.export_glb(os.path.join(out_dir, f"{gid}.glb"), B.collection_objects(col), animations=False)
    col = B.ensure_collection("objective_bomb")
    build_bomb(P, col)
    B.export_glb(os.path.join(out_dir, "bomb.glb"), B.collection_objects(col), animations=False)
    col = B.ensure_collection("objective_defuse_kit")
    build_defuse_kit(P, col)
    B.export_glb(os.path.join(out_dir, "defuse_kit.glb"), B.collection_objects(col), animations=False)
    col = B.ensure_collection("fx")
    build_shell_casing(P, col)
    B.export_glb(os.path.join(out_dir, "shell_casing.glb"), B.collection_objects(col), animations=False)
    B.validate_scene()
    B.save_blend("weapons.blend")


if __name__ == "__main__":
    main()
