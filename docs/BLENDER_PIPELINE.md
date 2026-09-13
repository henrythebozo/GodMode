# Blender asset pipeline

Every model is produced by a Python script so the whole asset set can be rebuilt reproducibly.

## Files

| Script | Produces |
|---|---|
| `blender/scripts/bl_common.py` | Shared helpers: scale/axis conventions, collections, materials, primitives, `join`, box-projection UVs, `apply_transforms`, LOD (`_LOD1`), collision (`-convcolonly`, `-colonly`, `-col`), naming validation, batch GLB export, `.blend` save. |
| `gen_weapons.py` | 16 firearms, knife, 5 grenades, demolition charge, defusal kit, shell casing → `breachline/assets/models/weapons/*.glb`, `blender/source/weapons.blend`. |
| `gen_characters.py` | Two rigged, skinned faction characters (17 bones, 9 animations) and the first-person arms rig (8 animations) → `characters/*.glb`, one `.blend` per rig. |
| `gen_environment_kit.py` | 28 modular pieces (walls, window wall, door frame/door, floors, stairs, catwalk, railing, ladder, crates, barrier, barrel, sandbags, pipes, lights, generator, furnace, silo, conveyor, console, lamp post, vent) → `environment/*.glb`, `environment_kit.blend`. |
| `gen_map_foundry.py` | The *Foundry* map: ASCII-grid design → merged, chunked geometry with trimesh collision and occluders + `foundry_layout.json` (spawns, sites, buy zones, callouts, ladders, cover points, patrol points, lights). |
| `export_all.py` | Runs all of the above. `regen_placeholders.py <category>` runs one. `validate_names.py file.blend` checks naming. |

## Conventions (enforced by `validate_scene()`)

* 1 unit = 1 m. Model forward is **+Y in Blender**, which the glTF exporter maps to Godot's **-Z**;
  right is +X in both. Weapons are drawn along -Y for convenience and mirrored by `mirror_forward()`.
* Object names: `snake_case` + Godot import suffixes (`-col`, `-convcolonly`, `-colonly`, `-occonly`,
  `_LOD1`). Marker empties are `<asset>_<marker>` (`p9_muzzle`, `corsair_eject`, `cinder_head`...) and
  Godot finds them by suffix (`find_child("*muzzle")`).
* Every mesh has a material (Principled BSDF: base colour, roughness, metallic, optional emission — all
  exported to Godot's StandardMaterial3D).
* Transforms are applied before export; the exporter triangulates.
* Bone names: `hips, spine, chest, neck, head, shoulder_l/r, upper_arm_l/r, forearm_l/r, hand_l/r,
  thigh_l/r, shin_l/r, foot_l/r, weapon_r`; FP arms: `root, upper_arm_*, forearm_*, hand_*, weapon`.
  Weapons attach with `BoneAttachment3D` + a holder rotated `(-90, 0, 180)` degrees.
* Animations are authored in armature space (`Rig.action`) and every action keys every bone so
  Godot animation switches never leave stale poses.

## Editing in Blender

1. `blender blender/source/weapons.blend` (or any other `.blend`). Collections are named per asset.
2. Edit meshes/materials/keyframes as usual. Keep the naming rules above (run
   *Scripting → Run Script* on `validate_names.py`, or `blender --background file.blend --python
   blender/scripts/validate_names.py`).
3. Export: select the asset's objects → *File → Export → glTF 2.0* (GLB, +Y up, Apply Modifiers,
   Animations on) into `breachline/assets/models/<category>/<id>.glb`. Or call
   `bl_common.export_glb(path, objects)` from the Python console.
4. Run `godot --headless --path breachline --import` (or open the editor) so Godot re-imports.

To change the procedural source instead, edit the generator (e.g. weapon dimensions in
`gen_weapons.FIREARMS`, the map in `gen_map_foundry.design()`) and re-run `export_all.py`.
The generated `.blend` files will be overwritten, so hand edits should be committed to a copy
or made the new source of truth by disabling that generator.

## Map design workflow

`gen_map_foundry.design()` carves a 60×50 grid of 2 m cells (`docs/MAP_FOUNDRY.txt` shows the
result as ASCII). Legend: `#` wall, `.` floor, `A`/`D` spawn floor, `a`/`b` bomb sites, `=` catwalk,
`<>^v` stairs, props `c C x s B g p v k F O K L h w l P`. Callouts, buy zones, spawns and sites are
named rectangles in the same grid; the layout JSON is written in Godot coordinates.
