class_name WeaponMeshFactory
extends RefCounted
## Instantiates the visual part of a weapon GLB (main mesh only, LOD/collision hidden) and
## exposes marker lookups.

static var _cache: Dictionary = {}


static func instantiate_weapon(id: String, first_person: bool) -> Node3D:
	var cfg := WeaponDB.get_config(id)
	if cfg == null:
		return null
	if not _cache.has(cfg.model):
		_cache[cfg.model] = load(cfg.model) if ResourceLoader.exists(cfg.model) else null
	var scene: PackedScene = _cache[cfg.model]
	if scene == null:
		return null
	var root: Node3D = scene.instantiate()
	for child in root.find_children("*", "", true, false):
		var n: String = child.name
		if n.ends_with("_LOD1") or n.ends_with("_LOD2") or n.ends_with("-convcol") or n.ends_with("-col") or n.ends_with("-colonly") or n.ends_with("_convcol") or n.ends_with("_col") or n.ends_with("_colonly"):
			child.visible = false
		elif child is StaticBody3D or child is CollisionShape3D:
			child.queue_free()
		elif child is MeshInstance3D and first_person:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func find_marker(root: Node3D, suffix: String) -> Node3D:
	if root == null:
		return null
	for child in root.find_children("*" + suffix, "", true, false):
		if child is Node3D:
			return child
	return null
