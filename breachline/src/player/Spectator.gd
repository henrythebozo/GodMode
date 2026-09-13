extends Node3D
## Camera for dead/spectating players: follow a teammate's first-person view or fly freely.

var cam: Camera3D
var target_id := 0
var free_cam := false
var yaw := 0.0
var pitch := 0.0
var active := false
var mouse_accum := Vector2.ZERO


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	cam = Camera3D.new()
	cam.fov = Settings.fov()
	add_child(cam)
	Events.local_player_died.connect(_on_local_died)
	Events.player_spawned.connect(func(id): if id == Net.local_id: stop())


func _on_local_died() -> void:
	var lp := Net.local_player()
	if lp == null:
		return
	get_tree().create_timer(2.0).timeout.connect(func(): if lp and not lp.alive: start())


func start() -> void:
	if cam == null:
		return
	active = true
	Net.spectating = true
	var lp := Net.local_player()
	if lp:
		global_position = lp.eye_position()
		yaw = lp.yaw
		pitch = lp.pitch
	free_cam = false
	_pick_next(1)
	cam.current = true
	Events.spectating_changed.emit(target_id, free_cam)


func stop() -> void:
	if not active:
		return
	active = false
	Net.spectating = false
	var lp := Net.local_player()
	if lp and lp.camera:
		lp.camera.current = true
	Events.spectating_changed.emit(0, false)


func _pick_next(dir: int) -> void:
	var lp := Net.local_player()
	var candidates := []
	for id in Net.players:
		var p: Player = Net.players[id]
		if p.alive and id != Net.local_id and (lp == null or p.team == lp.team or lp.team == Teams.SPECTATOR or Match.state == Match.State.MATCH_END):
			candidates.append(id)
	if candidates.is_empty():
		free_cam = true
		target_id = 0
		return
	candidates.sort()
	var idx := candidates.find(target_id)
	idx = posmod(idx + dir, candidates.size()) if idx >= 0 else 0
	target_id = candidates[idx]
	free_cam = false


func _input(event: InputEvent) -> void:
	if not active or Net.local_controller == null or Net.local_controller.ui_blocking:
		return
	if event is InputEventMouseMotion:
		mouse_accum += event.relative
	if event.is_action_pressed("spectate_next"):
		_pick_next(1)
		Events.spectating_changed.emit(target_id, free_cam)
	elif event.is_action_pressed("spectate_prev"):
		_pick_next(-1)
		Events.spectating_changed.emit(target_id, free_cam)
	elif event.is_action_pressed("spectate_free"):
		free_cam = not free_cam
		if free_cam:
			var t: Player = Net.players.get(target_id)
			if t:
				global_position = t.eye_position()
				yaw = t.yaw
				pitch = t.pitch
		Events.spectating_changed.emit(target_id, free_cam)


func _process(delta: float) -> void:
	if not active or cam == null:
		return
	var target: Player = Net.players.get(target_id)
	if not free_cam and (target == null or not target.alive):
		_pick_next(1)
		target = Net.players.get(target_id)
	if free_cam or target == null:
		var sens := Settings.mouse_sensitivity()
		yaw -= mouse_accum.x * sens
		pitch = clampf(pitch - mouse_accum.y * sens, -1.5, 1.5)
		mouse_accum = Vector2.ZERO
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var move := Vector3(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"), 0,
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
		if Input.is_action_pressed("jump"): move.y += 1
		if Input.is_action_pressed("crouch"): move.y -= 1
		var speed := 14.0 if not Input.is_action_pressed("walk") else 4.0
		global_position += b * move * speed * delta
		global_transform.basis = b
	else:
		mouse_accum = Vector2.ZERO
		global_position = target.eye_position()
		global_transform.basis = target.view_basis()
	cam.fov = Settings.fov()
