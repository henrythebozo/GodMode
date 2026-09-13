"""Generate rigged, animated character models for both factions and the first-person arms.

Factions (original):
  * cinder   - "Cinder Syndicate" attackers: dark hoodies, red armbands, balaclava-style heads.
  * aegis    - "Aegis Directorate" defenders: blue-grey tactical armour, visored helmets.

Each character: one skinned mesh (rigid per-bone weights, stylised low-poly), armature with
17 bones, weapon attachment bone `weapon_r`, hurtbox marker empties, LOD1, and animations:
  idle, walk, run, crouch_idle, crouch_walk, jump, death, plant, defuse
First-person arms: armature with shoulder/elbow/hand chains and a `weapon` bone, animations:
  idle, run, draw, fire, reload, inspect
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Vector, Matrix, Euler  # noqa: E402
import bl_common as B  # noqa: E402

FPS = 30


def cylinder_between(name, p1, p2, r1, r2, material, col, segments=8):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    length = d.length
    obj = B.cylinder(name, r1, length, (0, 0, 0), (0, 0, 0), material, col, segments, radius2=r2)
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    obj.matrix_world = Matrix.Translation((p1 + p2) * 0.5) @ rot
    return obj


class Rig:
    def __init__(self, name, col):
        self.arm_data = bpy.data.armatures.new(name)
        self.obj = bpy.data.objects.new(name, self.arm_data)
        col.objects.link(self.obj)
        bpy.context.view_layer.objects.active = self.obj
        self.bones = {}
        self.radius_scale = {}   # bone -> multiplier on distance (smaller = the bone "claims" more)
        self.col = col

    def add_bone(self, name, head, tail, parent=None):
        self.bones[name] = (Vector(head), Vector(tail), parent)

    def build(self):
        with bpy.context.temp_override(active_object=self.obj, object=self.obj, selected_objects=[self.obj]):
            bpy.ops.object.mode_set(mode="EDIT")
            for name, (head, tail, parent) in self.bones.items():
                eb = self.arm_data.edit_bones.new(name)
                eb.head, eb.tail = head, tail
                if parent:
                    eb.parent = self.arm_data.edit_bones[parent]
            bpy.ops.object.mode_set(mode="OBJECT")
        for pb in self.obj.pose.bones:
            pb.rotation_mode = "XYZ"

    def skin(self, mesh_obj, groups=None, exclude=("weapon_r", "weapon", "root")):
        """Rigid per-vertex weights: each vertex follows the bone whose segment is closest to it
        (distance to the head-tail segment, scaled by the bone's `radius` hint). `groups` (legacy
        predicate list) may override: the first matching predicate wins before the nearest-bone rule."""
        for bone in self.bones:
            mesh_obj.vertex_groups.new(name=bone)
        candidates = [(n, h, t) for n, (h, t, _p) in self.bones.items() if n not in exclude]

        def seg_dist(p, a, b):
            ab = b - a
            L2 = ab.length_squared
            if L2 < 1e-9:
                return (p - a).length
            u = max(0.0, min(1.0, (p - a).dot(ab) / L2))
            return (p - (a + ab * u)).length

        for v in mesh_obj.data.vertices:
            chosen = None
            if groups:
                for bone, pred in groups:
                    if pred(v.co):
                        chosen = bone
                        break
            if chosen is None:
                best = None
                bd = 1e9
                for n, h, t in candidates:
                    d = seg_dist(v.co, h, t) * self.radius_scale.get(n, 1.0)
                    if d < bd:
                        bd = d
                        best = n
                chosen = best
            mesh_obj.vertex_groups[chosen].add([v.index], 1.0, "REPLACE")
        mod = mesh_obj.modifiers.new("armature", "ARMATURE")
        mod.object = self.obj
        mesh_obj.parent = self.obj

    # --- animation helpers
    def action(self, name, frames, keys, loop=True, loc_keys=None):
        """keys: {bone: {frame: (rx, ry, rz)}} Euler degrees in ARMATURE (rest) space:
             +X tilts a bone's tip backwards (-Y) for upright bones / swings a hanging limb forward,
             +Z yaws, +Y rolls. loc_keys: {bone: {frame: (x, y, z)}} offsets in armature space.
           Both are converted to bone-local space here so authoring stays intuitive."""
        act = bpy.data.actions.new(name)
        act.use_frame_range = True
        act.frame_start, act.frame_end = 0, frames
        self.obj.animation_data_create()
        self.obj.animation_data.action = act
        for pb in self.obj.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
        # key every bone so switching animations in Godot never leaves stale poses behind
        keys = dict(keys)
        loc_keys = dict(loc_keys or {})
        for bone in self.bones:
            keys.setdefault(bone, {0: (0, 0, 0), frames: (0, 0, 0)})
            loc_keys.setdefault(bone, {0: (0, 0, 0), frames: (0, 0, 0)})
        for bone, fk in keys.items():
            pb = self.obj.pose.bones[bone]
            M = self.obj.data.bones[bone].matrix_local.to_3x3()
            for f, rot in sorted(fk.items()):
                R = Euler([math.radians(a) for a in rot], "XYZ").to_matrix()
                pb.rotation_quaternion = (M.inverted() @ R @ M).to_quaternion()
                pb.keyframe_insert("rotation_quaternion", frame=f)
        for bone, fk in loc_keys.items():
            pb = self.obj.pose.bones[bone]
            M = self.obj.data.bones[bone].matrix_local.to_3x3()
            for f, loc in sorted(fk.items()):
                pb.location = M.inverted() @ Vector(loc)
                pb.keyframe_insert("location", frame=f)
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
            if loop:
                fc.modifiers.new("CYCLES")
        # stash into NLA so the glTF exporter picks up every action
        track = self.obj.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        self.obj.animation_data.action = None
        act["loop"] = loop
        return act


# ---------------------------------------------------------------------------------- characters
def faction_palette(faction):
    if faction == "cinder":
        return {
            "skin": B.mat("cinder_skin", (0.1, 0.09, 0.09, 1), 0.9),        # balaclava
            "top": B.mat("cinder_top", (0.16, 0.14, 0.14, 1), 0.85),
            "vest": B.mat("cinder_vest", (0.09, 0.09, 0.1, 1), 0.7),
            "pants": B.mat("cinder_pants", (0.2, 0.18, 0.16, 1), 0.9),
            "boots": B.mat("cinder_boots", (0.08, 0.07, 0.06, 1), 0.8),
            "accent": B.mat("cinder_accent", (0.7, 0.1, 0.08, 1), 0.6),
            "glove": B.mat("cinder_glove", (0.12, 0.1, 0.09, 1), 0.9),
        }
    return {
        "skin": B.mat("aegis_skin", (0.72, 0.55, 0.42, 1), 0.8),
        "top": B.mat("aegis_top", (0.24, 0.3, 0.38, 1), 0.8),
        "vest": B.mat("aegis_vest", (0.14, 0.18, 0.24, 1), 0.65),
        "pants": B.mat("aegis_pants", (0.2, 0.24, 0.3, 1), 0.85),
        "boots": B.mat("aegis_boots", (0.1, 0.1, 0.11, 1), 0.7),
        "accent": B.mat("aegis_accent", (0.2, 0.6, 0.95, 1), 0.4, emission=(0.2, 0.6, 0.95, 1), emission_strength=0.8),
        "glove": B.mat("aegis_glove", (0.16, 0.18, 0.2, 1), 0.9),
    }


def build_character(faction, col):
    P = faction_palette(faction)
    parts = []
    # torso / pelvis
    parts.append(B.box("pelvis", (0.34, 0.22, 0.2), (0, 0, 0.95), material=P["pants"], collection=col, bevel=0.02))
    parts.append(B.box("torso", (0.38, 0.24, 0.42), (0, 0, 1.27), material=P["top"], collection=col, bevel=0.03))
    parts.append(B.box("vest", (0.4, 0.27, 0.3), (0, 0, 1.28), material=P["vest"], collection=col, bevel=0.02))
    parts.append(B.box("belt", (0.36, 0.24, 0.05), (0, 0, 1.06), material=P["boots"], collection=col))
    # head
    parts.append(B.cylinder("neck", 0.06, 0.08, (0, 0, 1.52), (0, 0, 0), P["skin"], col, 8))
    parts.append(B.box("head", (0.2, 0.22, 0.24), (0, 0.01, 1.66), material=P["skin"], collection=col, bevel=0.04))
    if faction == "aegis":
        parts.append(B.box("helmet", (0.24, 0.25, 0.14), (0, 0.0, 1.73), material=P["vest"], collection=col, bevel=0.05))
        parts.append(B.box("visor", (0.2, 0.03, 0.05), (0, 0.12, 1.68), material=P["accent"], collection=col))
    else:
        parts.append(B.box("hood", (0.24, 0.24, 0.1), (0, -0.02, 1.75), material=P["top"], collection=col, bevel=0.04))
        parts.append(B.box("eye_slit", (0.16, 0.02, 0.03), (0, 0.115, 1.68), material=B.mat("cinder_eyes", (0.8, 0.75, 0.7, 1), 0.5), collection=col))
    # arms (A-pose: hanging slightly out, then animated)
    for side, sx in (("l", -1), ("r", 1)):
        sh = Vector((sx * 0.24, 0, 1.45))
        el = Vector((sx * 0.30, -0.02, 1.17))
        wr = Vector((sx * 0.33, 0.0, 0.92))
        parts.append(cylinder_between(f"upper_arm_{side}", sh, el, 0.06, 0.05, P["top"], col))
        parts.append(cylinder_between(f"forearm_{side}", el, wr, 0.05, 0.04, P["top"], col))
        parts.append(B.box(f"hand_{side}", (0.08, 0.1, 0.09), wr + Vector((0, 0, -0.05)), material=P["glove"], collection=col, bevel=0.015))
        parts.append(B.sphere(f"shoulder_{side}", 0.075, sh, P["vest"], col, 8, 6))
        if faction == "cinder" and side == "l":
            parts.append(B.cylinder("armband", 0.065, 0.05, sh + Vector((sx * 0.03, -0.01, -0.14)), (0, sx * 12, 0), P["accent"], col, 8))
    # legs
    for side, sx in (("l", -1), ("r", 1)):
        hip = Vector((sx * 0.1, 0, 0.92))
        knee = Vector((sx * 0.11, 0.0, 0.5))
        ankle = Vector((sx * 0.11, 0.0, 0.08))
        parts.append(cylinder_between(f"thigh_{side}", hip, knee, 0.085, 0.07, P["pants"], col))
        parts.append(cylinder_between(f"shin_{side}", knee, ankle, 0.07, 0.055, P["pants"], col))
        parts.append(B.box(f"boot_{side}", (0.12, 0.26, 0.1), ankle + Vector((0, 0.04, -0.03)), material=P["boots"], collection=col, bevel=0.015))
        parts.append(B.sphere(f"kneepad_{side}", 0.075, knee + Vector((0, 0.02, 0)), P["vest"], col, 8, 6))
    body = B.join(parts, f"char_{faction}")
    B.box_uv(body, 0.5)
    B.shade_smooth(body, 45)
    B.apply_transforms(body)

    rig = Rig(f"rig_{faction}", col)
    rig.add_bone("hips", (0, 0, 0.95), (0, 0, 1.05))
    rig.add_bone("spine", (0, 0, 1.05), (0, 0, 1.25), "hips")
    rig.add_bone("chest", (0, 0, 1.25), (0, 0, 1.48), "spine")
    rig.add_bone("neck", (0, 0, 1.48), (0, 0, 1.56), "chest")
    rig.add_bone("head", (0, 0, 1.56), (0, 0, 1.80), "neck")
    for side, sx in (("l", -1), ("r", 1)):
        rig.add_bone(f"shoulder_{side}", (sx * 0.05, 0, 1.45), (sx * 0.24, 0, 1.45), "chest")
        rig.add_bone(f"upper_arm_{side}", (sx * 0.24, 0, 1.45), (sx * 0.30, -0.02, 1.17), f"shoulder_{side}")
        rig.add_bone(f"forearm_{side}", (sx * 0.30, -0.02, 1.17), (sx * 0.33, 0.0, 0.92), f"upper_arm_{side}")
        rig.add_bone(f"hand_{side}", (sx * 0.33, 0.0, 0.92), (sx * 0.33, 0.0, 0.80), f"forearm_{side}")
        rig.add_bone(f"thigh_{side}", (sx * 0.1, 0, 0.92), (sx * 0.11, 0, 0.5), "hips")
        rig.add_bone(f"shin_{side}", (sx * 0.11, 0, 0.5), (sx * 0.11, 0, 0.08), f"thigh_{side}")
        rig.add_bone(f"foot_{side}", (sx * 0.11, 0, 0.08), (sx * 0.11, 0.15, 0.02), f"shin_{side}")
    rig.add_bone("weapon_r", (0.33, 0.0, 0.86), (0.33, 0.0, 0.71), "hand_r")   # points forward in the hold pose
    rig.build()

    # torso/head bones are thick: let them claim vertices from further away than the limb bones
    rig.radius_scale = {"chest": 0.55, "spine": 0.7, "hips": 0.6, "head": 0.6, "neck": 0.9,
                        "shoulder_l": 1.4, "shoulder_r": 1.4, "hand_l": 0.8, "hand_r": 0.8, "foot_l": 0.8, "foot_r": 0.8}
    rig.skin(body, [("head", lambda co: co.z >= 1.58), ("hips", lambda co: 0.85 <= co.z < 1.06 and abs(co.x) < 0.2)])
    # hurtbox markers (read by Godot to build hit zones)
    B.empty("head", (0, 0, 1.66), (0, 0, 0), rig.obj, col, prefix=faction)
    B.empty("chest", (0, 0, 1.27), (0, 0, 0), rig.obj, col, prefix=faction)
    lod = B.make_lod(body, 0.5, 1)
    lod.parent = rig.obj
    for bone in rig.bones:
        if bone not in lod.vertex_groups:
            lod.vertex_groups.new(name=bone)
    lod.modifiers.new("armature", "ARMATURE").object = rig.obj
    character_animations(rig)
    return rig.obj


def character_animations(rig):
    # arms hold a rifle in every locomotion animation (rest-space: +X swings hanging arms forward)
    HOLD = {
        "upper_arm_r": (70, 0, 25), "forearm_r": (30, 0, 0),
        "upper_arm_l": (60, 0, -35), "forearm_l": (60, 0, 0),
    }

    def with_hold(keys, frames):
        for b, r in HOLD.items():
            keys.setdefault(b, {})
            for f in (0, frames):
                keys[b].setdefault(f, r)
        return keys

    F = 60
    rig.action("idle", F, with_hold({
        "chest": {0: (0, 0, 0), F // 2: (2, 0, 0), F: (0, 0, 0)},
        "head": {0: (0, 0, 0), F // 2: (2, 0, 3), F: (0, 0, 0)},
    }, F), loop=True)
    for name, F, amp, arm_amp, bob in (("walk", 40, 22, 6, 0.01), ("run", 24, 40, 14, 0.03)):
        keys = {
            "thigh_l": {0: (amp, 0, 0), F // 2: (-amp, 0, 0), F: (amp, 0, 0)},
            "thigh_r": {0: (-amp, 0, 0), F // 2: (amp, 0, 0), F: (-amp, 0, 0)},
            "shin_l": {0: (0, 0, 0), F // 4: (-amp * 1.2, 0, 0), F // 2: (0, 0, 0), F: (0, 0, 0)},
            "shin_r": {0: (0, 0, 0), F // 2: (0, 0, 0), 3 * F // 4: (-amp * 1.2, 0, 0), F: (0, 0, 0)},
            "spine": {0: (-6, 0, 0), F: (-6, 0, 0)},
            "chest": {0: (0, 0, -arm_amp * 0.4), F // 2: (0, 0, arm_amp * 0.4), F: (0, 0, -arm_amp * 0.4)},
        }
        rig.action(name, F, with_hold(keys, F), loop=True,
                   loc_keys={"hips": {0: (0, 0, 0), F // 4: (0, 0, -bob), F // 2: (0, 0, 0), 3 * F // 4: (0, 0, -bob), F: (0, 0, 0)}})
    CROUCH = {"thigh_l": (75, 0, 0), "thigh_r": (75, 0, 0), "shin_l": (-95, 0, 0), "shin_r": (-95, 0, 0),
              "spine": (-25, 0, 0), "chest": (-10, 0, 0), "head": (30, 0, 0)}
    F = 40
    rig.action("crouch_idle", F, with_hold({b: {0: r, F: r} for b, r in CROUCH.items()}, F), loop=True,
               loc_keys={"hips": {0: (0, 0, -0.45), F: (0, 0, -0.45)}})
    keys = {b: {0: r, F: r} for b, r in CROUCH.items()}
    keys["thigh_l"] = {0: (60, 0, 0), F // 2: (90, 0, 0), F: (60, 0, 0)}
    keys["thigh_r"] = {0: (90, 0, 0), F // 2: (60, 0, 0), F: (90, 0, 0)}
    rig.action("crouch_walk", F, with_hold(keys, F), loop=True,
               loc_keys={"hips": {0: (0, 0, -0.45), F: (0, 0, -0.45)}})
    F = 20
    rig.action("jump", F, with_hold({
        "thigh_l": {0: (0, 0, 0), 8: (50, 0, 0), F: (10, 0, 0)},
        "thigh_r": {0: (0, 0, 0), 8: (40, 0, 0), F: (10, 0, 0)},
        "shin_l": {0: (0, 0, 0), 8: (-70, 0, 0), F: (-20, 0, 0)},
        "shin_r": {0: (0, 0, 0), 8: (-60, 0, 0), F: (-20, 0, 0)},
    }, F), loop=False)
    F = 30
    rig.action("death", F, {
        "hips": {0: (0, 0, 0), F: (80, 0, 15)},
        "spine": {0: (0, 0, 0), 10: (10, 0, 0), F: (-5, 0, 0)},
        "head": {0: (0, 0, 0), F: (30, 0, 20)},
        "upper_arm_r": {0: HOLD["upper_arm_r"], F: (20, 0, 80)},
        "upper_arm_l": {0: HOLD["upper_arm_l"], F: (10, 0, -85)},
        "forearm_r": {0: HOLD["forearm_r"], F: (20, 0, 0)},
        "forearm_l": {0: HOLD["forearm_l"], F: (30, 0, 0)},
        "thigh_l": {0: (0, 0, 0), F: (-20, 0, 10)}, "thigh_r": {0: (0, 0, 0), F: (-35, 0, -15)},
        "shin_l": {0: (0, 0, 0), F: (-30, 0, 0)},
    }, loop=False, loc_keys={"hips": {0: (0, 0, 0), F: (0, -0.3, -0.85)}})
    for name in ("plant", "defuse"):
        F = 90
        arm = "r" if name == "plant" else "l"
        keys = {b: {0: (0, 0, 0), 15: r, F: r} for b, r in CROUCH.items()}
        keys[f"upper_arm_{arm}"] = {0: HOLD[f"upper_arm_{arm}"], 15: (45, 0, 0), 45: (55, 0, 0), 75: (45, 0, 0), F: (50, 0, 0)}
        keys[f"forearm_{arm}"] = {0: HOLD[f"forearm_{arm}"], 15: (20, 0, 0), 45: (10, 0, 0), 75: (20, 0, 0), F: (15, 0, 0)}
        other = "l" if arm == "r" else "r"
        keys[f"upper_arm_{other}"] = {0: HOLD[f"upper_arm_{other}"], 15: (30, 0, 0), F: (30, 0, 0)}
        keys[f"forearm_{other}"] = {0: HOLD[f"forearm_{other}"], 15: (20, 0, 0), F: (20, 0, 0)}
        rig.action(name, F, keys, loop=False, loc_keys={"hips": {0: (0, 0, 0), 15: (0, 0, -0.45), F: (0, 0, -0.45)}})


# ---------------------------------------------------------------------------------- first person arms
def build_fp_arms(col):
    sleeve = B.mat("fp_sleeve", (0.16, 0.17, 0.18, 1), 0.85)
    glove = B.mat("fp_glove", (0.1, 0.09, 0.08, 1), 0.9)
    strap = B.mat("fp_strap", (0.35, 0.3, 0.2, 1), 0.8)
    parts = []
    # camera at origin, forward +Y, up Z. Right hand grips near (0.13, 0.32, -0.17)
    chains = {
        "r": [Vector((0.22, -0.02, -0.28)), Vector((0.26, 0.12, -0.32)), Vector((0.13, 0.32, -0.17))],
        "l": [Vector((-0.22, -0.02, -0.28)), Vector((-0.18, 0.30, -0.34)), Vector((-0.02, 0.50, -0.19))],
    }
    for side, (sh, el, wr) in chains.items():
        parts.append(cylinder_between(f"upper_{side}", sh, el, 0.058, 0.05, sleeve, col, 10))
        parts.append(cylinder_between(f"fore_{side}", el, wr, 0.05, 0.042, sleeve, col, 10))
        parts.append(B.sphere(f"elbow_{side}", 0.052, el, sleeve, col, 8, 6))
        parts.append(cylinder_between(f"cuff_{side}", el + (wr - el) * 0.8, wr, 0.046, 0.046, strap, col, 10))
        d = (wr - el).normalized()
        palm_c = wr + d * 0.05
        hand = B.box(f"palm_{side}", (0.075, 0.1, 0.045), (0, 0, 0), material=glove, collection=col, bevel=0.012)
        hand.matrix_world = Matrix.Translation(palm_c) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
        parts.append(hand)
        for i in range(4):
            f = B.box(f"finger_{side}{i}", (0.016, 0.06, 0.016), (0, 0, 0), material=glove, collection=col, bevel=0.004)
            local = Vector((-0.027 + i * 0.018, 0.07, -0.01))
            f.matrix_world = Matrix.Translation(palm_c) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4() @ Matrix.Translation(local) @ Matrix.Rotation(math.radians(60), 4, "X")
            parts.append(f)
        th = B.box(f"thumb_{side}", (0.016, 0.05, 0.016), (0, 0, 0), material=glove, collection=col, bevel=0.004)
        th.matrix_world = Matrix.Translation(palm_c) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4() @ Matrix.Translation(Vector((-0.045 if side == "r" else 0.045, 0.02, 0.01))) @ Matrix.Rotation(math.radians(-30 if side == "r" else 30), 4, "Z")
        parts.append(th)
    body = B.join(parts, "fp_arms")
    B.box_uv(body, 0.3)
    B.shade_smooth(body, 45)
    B.apply_transforms(body)

    rig = Rig("rig_fp_arms", col)
    rig.add_bone("root", (0, 0, -0.3), (0, 0.1, -0.3))
    for side, (sh, el, wr) in chains.items():
        rig.add_bone(f"upper_arm_{side}", sh, el, "root")
        rig.add_bone(f"forearm_{side}", el, wr, f"upper_arm_{side}")
        rig.add_bone(f"hand_{side}", wr, wr + (wr - el).normalized() * 0.1, f"forearm_{side}")
    rig.add_bone("weapon", (0.13, 0.30, -0.15), (0.13, 0.45, -0.15), "hand_r")
    rig.build()

    def near_chain(side, seg):
        sh, el, wr = chains[side]
        a, b = {"upper": (sh, el), "fore": (el, wr), "hand": (wr, wr + (wr - el).normalized() * 0.2)}[seg]

        def pred(co):
            if (co.x > 0) != (side == "r"):
                return False
            ab = b - a
            t = (co - a).dot(ab) / ab.length_squared
            return -0.15 <= t <= (1.15 if seg != "hand" else 9.0)
        return pred

    rig.radius_scale = {"hand_r": 0.5, "hand_l": 0.5}
    rig.skin(body)
    fp_animations(rig)
    return rig.obj


def fp_animations(rig):
    # rest-space conventions: root points +Y (forward); +X rotation lifts the muzzle, -Y offset pulls back
    F = 60
    rig.action("idle", F, {
        "root": {0: (0, 0, 0), F // 2: (1.2, 0, 0.6), F: (0, 0, 0)},
    }, loop=True, loc_keys={"root": {0: (0, 0, 0), F // 2: (0, -0.004, -0.004), F: (0, 0, 0)}})
    F = 20
    rig.action("run", F, {
        "root": {0: (0, 0, -3), F // 2: (2, 0, 3), F: (0, 0, -3)},
    }, loop=True, loc_keys={"root": {0: (0, 0, 0), F // 4: (0.01, -0.01, -0.015), F // 2: (0, 0, 0), 3 * F // 4: (-0.01, -0.01, -0.015), F: (0, 0, 0)}})
    F = 12
    rig.action("draw", F, {"root": {0: (-35, 0, 0), F: (0, 0, 0)}}, loop=False,
               loc_keys={"root": {0: (0, -0.1, -0.25), F: (0, 0, 0)}})
    F = 6
    rig.action("fire", F, {"root": {0: (0, 0, 0), 1: (4, 0, 0), F: (0, 0, 0)}}, loop=False,
               loc_keys={"root": {0: (0, 0, 0), 1: (0, -0.03, 0.005), F: (0, 0, 0)}})
    F = 60
    rig.action("reload", F, {
        "upper_arm_l": {0: (0, 0, 0), 12: (-30, 0, 20), 30: (-45, 0, 25), 48: (-10, 0, 5), F: (0, 0, 0)},
        "forearm_l": {0: (0, 0, 0), 12: (20, 0, 0), 30: (35, 0, 0), 48: (10, 0, 0), F: (0, 0, 0)},
        "root": {0: (0, 0, 0), 12: (-8, 0, -6), 40: (-8, 0, -6), F: (0, 0, 0)},
    }, loop=False)
    F = 80
    rig.action("inspect", F, {
        "root": {0: (0, 0, 0), 20: (-10, 25, 20), 45: (5, -35, 30), 65: (-10, 10, -10), F: (0, 0, 0)},
        "upper_arm_l": {0: (0, 0, 0), 20: (-10, 0, 15), 45: (-20, 0, -10), F: (0, 0, 0)},
    }, loop=False, loc_keys={"root": {0: (0, 0, 0), 30: (0.03, -0.05, -0.02), F: (0, 0, 0)}})
    F = 20
    rig.action("melee", F, {"root": {0: (0, 0, 0), 5: (15, 0, 25), 12: (-25, 0, -30), F: (0, 0, 0)}}, loop=False)
    F = 24
    rig.action("throw", F, {"root": {0: (0, 0, 0), 8: (20, 0, 15), 14: (-30, 0, -20), F: (0, 0, 0)}}, loop=False)


def main():
    # One scene per rigged asset: the glTF exporter samples every action it can find against the
    # armature, so rigs with different bone sets must not share a file.
    out = os.path.join(B.GODOT_MODELS, "characters")
    for faction in ("cinder", "aegis"):
        B.reset_scene()
        col = B.ensure_collection(f"character_{faction}")
        build_character(faction, col)
        B.validate_scene()
        B.export_glb(os.path.join(out, f"{faction}.glb"), B.collection_objects(col))
        B.save_blend(f"character_{faction}.blend")
    B.reset_scene()
    col = B.ensure_collection("fp_arms")
    build_fp_arms(col)
    B.validate_scene()
    B.export_glb(os.path.join(out, "fp_arms.glb"), B.collection_objects(col))
    B.save_blend("fp_arms.blend")


if __name__ == "__main__":
    main()
