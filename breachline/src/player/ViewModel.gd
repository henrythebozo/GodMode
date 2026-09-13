extends Node3D
## First-person arms + weapon under the camera. Handles draw/fire/reload/inspect animations,
## sway, bob, recoil kick and zoom. Purely presentational (reads Player state).

var player: Player
var arms: Node3D
var anim: AnimationPlayer
var weapon_holder: Node3D
var weapon_node: Node3D
var current_id := ""
var base_offset := Vector3.ZERO
var sway := Vector2.ZERO
var bob_time := 0.0
var last_shots := 0
var was_reloading := false
var was_inspecting := false
var last_equip_timer := 0.0
var muzzle: Node3D
var eject: Node3D
var mouse_delta := Vector2.ZERO
var base_fov := 68.0
var target_fov_scale := 1.0


func setup(p: Player) -> void:
	player = p
	var scene: PackedScene = load("res://assets/models/characters/fp_arms.glb") if ResourceLoader.exists("res://assets/models/characters/fp_arms.glb") else null
	if scene:
		arms = scene.instantiate()
		add_child(arms)
		anim = arms.find_child("AnimationPlayer", true, false)
		var skel: Skeleton3D = arms.find_child("Skeleton3D", true, false)
		for mi in arms.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if skel and skel.find_bone("weapon") >= 0:
			var att := BoneAttachment3D.new()
			att.bone_name = "weapon"
			skel.add_child(att)
			weapon_holder = Node3D.new()
			weapon_holder.rotation_degrees = Vector3(-90, 0, 180)
			att.add_child(weapon_holder)
		if anim:
			anim.playback_default_blend_time = 0.08
	if weapon_holder == null:
		weapon_holder = Node3D.new()
		add_child(weapon_holder)
	base_fov = float(Settings.get_value("video", "viewmodel_fov", 68.0))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_delta += event.relative


func _process(delta: float) -> void:
	if player == null:
		return
	var w := player.active_weapon()
	var id := w.cfg.id if w and player.alive else ""
	if id != current_id:
		_swap_weapon(id, w)
	visible = player.alive and not Net.spectating
	if w == null or not player.alive:
		return
	# animation triggers from weapon state transitions
	if w.equip_timer > 0.0 and last_equip_timer <= 0.0:
		_play("draw")
	last_equip_timer = w.equip_timer
	var reloading := w.reload_timer >= 0.0
	if reloading and not was_reloading:
		_play("reload", w.cfg.reload_time_empty if w.ammo == 0 else w.cfg.reload_time)
	was_reloading = reloading
	var inspecting := w.inspect_timer >= 0.0
	if inspecting and not was_inspecting:
		_play("inspect", 2.6)
	was_inspecting = inspecting
	if w.consecutive_shots > last_shots and w.consecutive_shots > 0:
		_play("fire")
	last_shots = w.consecutive_shots
	if player.melee_timer >= 0.0 and anim and anim.current_animation != "melee":
		_play("melee")
	if player.throw_timer >= 0.0 and anim and anim.current_animation != "throw":
		_play("throw")
	if anim and not anim.is_playing():
		_play("run" if player.horizontal_speed() > 3.0 and player.is_on_floor() else "idle")
	# sway / bob / recoil
	var reduced := bool(Settings.get_value("video", "reduced_motion", false))
	var sway_target := Vector2.ZERO if reduced else Vector2(-mouse_delta.x, -mouse_delta.y) * 0.0006
	mouse_delta = Vector2.ZERO
	sway = sway.lerp(sway_target.limit_length(0.03), clampf(delta * 10.0, 0.0, 1.0))
	var speed := player.horizontal_speed()
	if player.is_on_floor() and speed > 0.5 and not reduced:
		bob_time += delta * clampf(speed / 5.4, 0.3, 1.5) * 11.0
	var bob := Vector3(sin(bob_time) * 0.006, abs(cos(bob_time)) * 0.006, 0.0) * clampf(speed / 5.4, 0.0, 1.0)
	if reduced:
		bob = Vector3.ZERO
	var kick := Vector3(0, deg_to_rad(player.recoil_offset.y) * 0.02, deg_to_rad(player.recoil_offset.y) * 0.05)
	var crouch_offset := Vector3(0, -0.02, 0) * player.crouch_amount
	var zoom_hide := Vector3(0, -0.25, 0.05) if player.zoomed and w.cfg.category == "sniper" else Vector3.ZERO
	position = base_offset + Vector3(sway.x, sway.y, 0) + bob + kick + crouch_offset + zoom_hide
	rotation = Vector3(deg_to_rad(player.recoil_offset.y) * 0.4, deg_to_rad(-player.recoil_offset.x) * 0.4, sway.x * 4.0)
	# camera zoom
	var cam := player.camera
	if cam:
		var zoom := 1.0
		if player.zoomed and not w.cfg.zoom_levels.is_empty():
			zoom = w.cfg.zoom_levels[clampi(w.zoom_level, 0, w.cfg.zoom_levels.size() - 1)]
		var target := Settings.fov() / zoom
		cam.fov = lerpf(cam.fov, target, clampf(delta * 14.0, 0.0, 1.0))


func _swap_weapon(id: String, w: WeaponState) -> void:
	current_id = id
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
	muzzle = null
	eject = null
	last_shots = 0
	was_reloading = false
	last_equip_timer = 0.0
	if id.is_empty():
		return
	weapon_node = WeaponMeshFactory.instantiate_weapon(id, true)
	if weapon_node:
		weapon_holder.add_child(weapon_node)
		muzzle = WeaponMeshFactory.find_marker(weapon_node, "muzzle")
		eject = WeaponMeshFactory.find_marker(weapon_node, "eject")
	base_offset = w.cfg.fp_offset - Vector3(0.13, -0.17, -0.32) if w else Vector3.ZERO
	_play("draw")


func _play(name: String, fit_duration: float = -1.0) -> void:
	if anim == null or not anim.has_animation(name):
		return
	var a := anim.get_animation(name)
	a.loop_mode = Animation.LOOP_LINEAR if name in ["idle", "run"] else Animation.LOOP_NONE
	var speed := 1.0
	if fit_duration > 0.0 and a.length > 0.0:
		speed = a.length / fit_duration
	anim.play(name, -1, speed)


func muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position + global_transform.basis * Vector3(0, 0, -0.5)


func eject_transform() -> Transform3D:
	if eject:
		return eject.global_transform
	return global_transform
