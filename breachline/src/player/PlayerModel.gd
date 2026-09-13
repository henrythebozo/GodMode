extends Node3D
## Third-person character: faction mesh + AnimationPlayer driven by the body state, weapon held on
## the `weapon_r` bone, aim pitch layered onto the chest bone after the animation advances.

var player: Player
var anim: AnimationPlayer
var skeleton: Skeleton3D
var attachment: BoneAttachment3D
var weapon_holder: Node3D
var current_weapon_id := ""
var current_anim := ""
var chest_idx := -1
var head_idx := -1
var scene_root: Node3D
static var _scene_cache: Dictionary = {}


static func load_scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[path]


func setup(p: Player) -> void:
	player = p
	var scene := load_scene(Teams.faction_model(p.team))
	if scene == null:
		return
	scene_root = scene.instantiate()
	add_child(scene_root)
	anim = scene_root.find_child("AnimationPlayer", true, false)
	skeleton = scene_root.find_child("Skeleton3D", true, false)
	for child in scene_root.find_children("*_LOD1", "", true, false):
		child.visible = false
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.playback_default_blend_time = 0.12
	if skeleton:
		chest_idx = skeleton.find_bone("chest")
		head_idx = skeleton.find_bone("head")
		var w_idx := skeleton.find_bone("weapon_r")
		if w_idx >= 0:
			attachment = BoneAttachment3D.new()
			attachment.bone_name = "weapon_r"
			skeleton.add_child(attachment)
			weapon_holder = Node3D.new()
			weapon_holder.rotation_degrees = Vector3(-90, 0, 180)
			attachment.add_child(weapon_holder)


func set_alive(a: bool) -> void:
	if not a:
		_play("death")


func update_pose(delta: float) -> void:
	if anim == null:
		return
	var p := player
	var target := "idle"
	if not p.alive:
		target = "death"
	elif p.planting:
		target = "plant"
	elif p.defusing:
		target = "defuse"
	elif p.on_ladder:
		target = "walk"
	elif not p.was_on_floor:
		target = "jump"
	elif p.crouch_amount > 0.5:
		target = "crouch_walk" if p.horizontal_speed() > 0.5 else "crouch_idle"
	elif p.horizontal_speed() > 0.5:
		target = "walk" if p.walking or p.horizontal_speed() < 3.0 else "run"
	_play(target)
	var speed_scale := 1.0
	if target == "run":
		speed_scale = clampf(p.horizontal_speed() / 5.4, 0.6, 1.4)
	anim.speed_scale = speed_scale
	anim.advance(delta)
	if skeleton and chest_idx >= 0 and p.alive:
		var q := Quaternion(Vector3.RIGHT, p.pitch * 0.6)
		skeleton.set_bone_pose_rotation(chest_idx, skeleton.get_bone_pose_rotation(chest_idx) * q)
	_update_weapon()


func _play(name: String) -> void:
	if current_anim == name or not anim.has_animation(name):
		return
	current_anim = name
	var a := anim.get_animation(name)
	a.loop_mode = Animation.LOOP_LINEAR if name in ["idle", "walk", "run", "crouch_idle", "crouch_walk"] else Animation.LOOP_NONE
	anim.play(name)


func _update_weapon() -> void:
	if weapon_holder == null:
		return
	var cfg := player.active_config()
	var id := cfg.id if cfg and player.alive else ""
	if id == current_weapon_id:
		return
	current_weapon_id = id
	for c in weapon_holder.get_children():
		c.queue_free()
	if id.is_empty():
		return
	var mesh := WeaponMeshFactory.instantiate_weapon(id, false)
	if mesh:
		weapon_holder.add_child(mesh)
