"""Shared Blender (bpy) helpers for the Breachline asset pipeline.

Conventions enforced here:
  * 1 Blender unit == 1 metre. Z is up in Blender; the glTF exporter converts to Godot's Y-up.
  * Model "forward" is +Y in Blender: the glTF exporter maps Blender +Y to Godot -Z (Godot's forward),
    so right stays +X and no runtime rotation is needed. Weapon builders draw along -Y for
    convenience and call mirror_forward() once at the end.
  * Object names use snake_case; Godot import suffixes are appended verbatim:
      -col      trimesh collision built from this mesh
      -convcolonly  convex collision only (mesh not rendered)
      -colonly  collision only (mesh not rendered)
      -occonly  occluder only (mesh not rendered)
      _LOD1/_LOD2  decimated LOD meshes
  * Marker empties are named: muzzle, eject, grip_r, grip_l, mag_socket, sight, hand_r, hand_l.
  * Every exported object lives in a collection named after the asset category.

Works both as a script run inside Blender (`blender --background --python ...`) and with the
`bpy` pip module (`python export_all.py`).
"""
import math
import os
import re
import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT_MODELS = os.path.join(ROOT, "breachline", "assets", "models")
BLEND_SOURCE = os.path.join(ROOT, "blender", "source")

NAME_RE = re.compile(r"^[a-z][a-z0-9_]*(-col|-convcol|-convcolonly|-colonly|-occ|-occonly)?(_LOD[12])?$")
MARKER_NAMES = {"muzzle", "eject", "grip_r", "grip_l", "mag_socket", "sight", "hand_r", "hand_l",
                "attach_top", "attach_barrel", "origin_fp", "origin_tp", "pin", "head", "chest"}
# Markers are prefixed with the asset id (e.g. "p9_muzzle") so several assets can share a .blend.
# Godot resolves them by suffix: find_child("*muzzle").
MARKER_RE = re.compile(r"^(?:[a-z0-9]+_)*(" + "|".join(sorted(MARKER_NAMES, key=len, reverse=True)) + r")$")


_MAT_CACHE = {}


# --------------------------------------------------------------------------- scene management
def reset_scene():
    _MAT_CACHE.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30
    return scene


def ensure_collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    return col


def link(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


# --------------------------------------------------------------------------- materials
def mat(name, color=(0.5, 0.5, 0.5, 1.0), roughness=0.6, metallic=0.0, emission=None, emission_strength=1.0):
    """Godot-friendly Principled BSDF material (base colour, roughness, metallic, optional emission)."""
    if name in _MAT_CACHE and _MAT_CACHE[name].name in bpy.data.materials:
        return _MAT_CACHE[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    m.diffuse_color = color
    _MAT_CACHE[name] = m
    return m


# --------------------------------------------------------------------------- mesh primitives
def _finish(bm, name, material, collection, location=(0, 0, 0), rotation=(0, 0, 0), bevel=0.0):
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    obj.rotation_euler = Euler([math.radians(a) for a in rotation])
    if material is not None:
        me.materials.append(material)
    if collection is not None:
        collection.objects.link(obj)
    return obj


def box(name, size, location=(0, 0, 0), rotation=(0, 0, 0), material=None, collection=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return _finish(bm, name, material, collection, location, rotation, bevel)


def cylinder(name, radius, depth, location=(0, 0, 0), rotation=(0, 0, 0), material=None, collection=None,
             segments=12, radius2=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    return _finish(bm, name, material, collection, location, rotation, bevel)


def sphere(name, radius, location=(0, 0, 0), material=None, collection=None, segments=12, rings=8):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    return _finish(bm, name, material, collection, location)


def plane(name, size_x, size_y, location=(0, 0, 0), rotation=(0, 0, 0), material=None, collection=None):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    bmesh.ops.scale(bm, vec=Vector((size_x, size_y, 1.0)), verts=bm.verts)
    return _finish(bm, name, material, collection, location, rotation)


def empty(name, location=(0, 0, 0), rotation=(0, 0, 0), parent=None, collection=None, size=0.05, prefix=None):
    if prefix:
        name = f"{prefix}_{name}"
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    e.location = location
    e.rotation_euler = Euler([math.radians(a) for a in rotation])
    if parent is not None:
        e.parent = parent
    (collection or bpy.context.scene.collection).objects.link(e)
    return e


# --------------------------------------------------------------------------- mesh operations
def sync():
    """Flush pending transform edits so matrix_world is up to date (bpy does not do this on assignment)."""
    bpy.context.view_layer.update()


def join(objects, name, material_override=None):
    """Join a list of mesh objects into one object (world-space transforms baked in)."""
    sync()
    bm = bmesh.new()
    mats = []
    for ob in objects:
        me = ob.data
        for m in me.materials:
            if m not in mats:
                mats.append(m)
    mat_index = {m: i for i, m in enumerate(mats)}
    for ob in objects:
        ob_bm = bmesh.new()
        ob_bm.from_mesh(ob.data)
        bmesh.ops.transform(ob_bm, matrix=ob.matrix_world, verts=ob_bm.verts)
        ob_mats = list(ob.data.materials)
        for f in ob_bm.faces:
            src = ob_mats[f.material_index] if ob_mats else None
            f.material_index = mat_index.get(src, 0)
        tmp = bpy.data.meshes.new("_tmp")
        ob_bm.to_mesh(tmp)
        ob_bm.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    col = objects[0].users_collection[0] if objects[0].users_collection else bpy.context.scene.collection
    col.objects.link(obj)
    for ob in objects:
        bpy.data.objects.remove(ob, do_unlink=True)
    if material_override is not None:
        me.materials.clear()
        me.materials.append(material_override)
    return obj


def box_uv(obj, scale=1.0):
    """Triplanar box projection so every face has sane, non-overlapping-ish UVs at a fixed texel density."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                uv = (co.x, co.y)
            elif ax >= ay:
                uv = (co.y, co.z)
            else:
                uv = (co.x, co.z)
            loop[uv_layer].uv = (uv[0] / scale, uv[1] / scale)
    bm.to_mesh(me)
    bm.free()


def shade_smooth(obj, angle_deg=35.0):
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    if hasattr(me, "set_sharp_from_angle"):
        me.set_sharp_from_angle(angle=math.radians(angle_deg))


def apply_transforms(obj):
    """Bake location/rotation/scale into mesh data (equivalent to Ctrl+A > All Transforms)."""
    if obj.type != "MESH":
        return
    me = obj.data
    me.transform(obj.matrix_basis)
    obj.matrix_basis = Matrix.Identity(4)


def make_lod(obj, ratio, level):
    """Decimated copy named <name>_LOD<level>."""
    sync()
    lod = obj.copy()
    lod.data = obj.data.copy()
    lod.name = f"{obj.name}_LOD{level}"
    lod.data.name = lod.name
    for c in obj.users_collection:
        c.objects.link(lod)
    mod = lod.modifiers.new("decimate", "DECIMATE")
    mod.ratio = ratio
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = lod.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(eval_obj)
    new_mesh.validate(clean_customdata=False)
    for m in obj.data.materials:
        new_mesh.materials.append(m)
    old = lod.data
    lod.data = new_mesh
    lod.modifiers.clear()
    bpy.data.meshes.remove(old)
    new_mesh.name = lod.name
    lod.parent = obj.parent
    lod.matrix_world = obj.matrix_world
    return lod


def make_convex_collision(obj, name=None):
    """Convex hull collision-only mesh (-convcolonly suffix), used by Godot's glTF importer."""
    sync()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    hull = bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.delete(bm, geom=hull["geom_interior"] + hull["geom_unused"], context="VERTS")
    me = bpy.data.meshes.new((name or obj.name) + "-convcolonly")
    bm.to_mesh(me)
    bm.free()
    col = bpy.data.objects.new(me.name, me)
    col.parent = obj.parent
    col.matrix_world = obj.matrix_world
    col.display_type = "WIRE"
    for c in obj.users_collection:
        c.objects.link(col)
    return col


def make_box_collision(obj, name=None, colonly=True):
    """Axis-aligned bounding box collision (-colonly) for props."""
    sync()
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    center = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)
    suffix = "-colonly" if colonly else "-col"
    col = box((name or obj.name) + suffix, size, material=None, collection=None)
    col.data.transform(Matrix.Translation(Vector(center)))
    col.parent = obj.parent
    col.matrix_world = obj.matrix_world
    col.display_type = "WIRE"
    for c in obj.users_collection:
        c.objects.link(col)
    return col


def mirror_forward(obj):
    """Flip a (non-rigged) mesh and its marker children from -Y-forward to +Y-forward."""
    if obj.type == "MESH":
        obj.data.transform(Matrix.Scale(-1.0, 4, Vector((0, 1, 0))))
        obj.data.flip_normals()
    for ch in obj.children:
        if ch.type == "EMPTY":
            ch.location.y *= -1.0
        elif ch.type == "MESH":
            ch.data.transform(Matrix.Scale(-1.0, 4, Vector((0, 1, 0))))
            ch.data.flip_normals()


# --------------------------------------------------------------------------- validation
def validate_scene(strict=True):
    """Naming/transform validation. Returns list of problems (raises when strict)."""
    problems = []
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            if not NAME_RE.match(ob.name):
                problems.append(f"bad mesh name: {ob.name}")
            if ob.parent is None and (ob.scale - Vector((1, 1, 1))).length > 1e-6:
                problems.append(f"unapplied scale on: {ob.name}")
            if not ob.data.materials and not ob.name.endswith(("-colonly", "-convcol", "-convcolonly", "-occ", "-occonly", "-col")):
                problems.append(f"no material on: {ob.name}")
        elif ob.type == "EMPTY":
            if not MARKER_RE.match(ob.name):
                problems.append(f"bad marker name: {ob.name}")
        elif ob.type == "ARMATURE":
            if not NAME_RE.match(ob.name):
                problems.append(f"bad armature name: {ob.name}")
    if problems and strict:
        raise RuntimeError("Validation failed:\n  " + "\n  ".join(problems))
    return problems


# --------------------------------------------------------------------------- export
def select_only(objects):
    vl = bpy.context.view_layer
    for ob in bpy.data.objects:
        ob.select_set(False)
    for ob in objects:
        ob.select_set(True)
    if objects:
        vl.objects.active = objects[0]


def export_glb(path, objects, animations=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    select_only(objects)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,          # applies modifiers + triangulates on export
        export_yup=True,
        export_animations=animations,
        export_skins=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_extras=True,
        export_lights=False,
        export_cameras=False,
    )
    print(f"[export] {os.path.relpath(path, ROOT)}  ({len(objects)} objects)")


def save_blend(name):
    os.makedirs(BLEND_SOURCE, exist_ok=True)
    path = os.path.join(BLEND_SOURCE, name)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print(f"[blend]  {os.path.relpath(path, ROOT)}")
    return path


def collection_objects(col, recursive=True):
    out = list(col.objects)
    if recursive:
        for child in col.children:
            out += collection_objects(child, True)
    return out
