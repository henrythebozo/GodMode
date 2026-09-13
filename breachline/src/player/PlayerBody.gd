class_name PlayerBody
extends CharacterBody3D
## Deterministic-enough movement simulation shared by server, client prediction and bots.
## Everything that changes position goes through simulate(cmd, dt).

const GRAVITY := 15.0
const JUMP_VELOCITY := 5.6
const GROUND_ACCEL := 60.0
const GROUND_FRICTION := 8.0
const AIR_ACCEL := 8.0
const AIR_MAX_WISH := 1.2
const WALK_MULT := 0.52
const CROUCH_MULT := 0.34
const LADDER_SPEED := 2.6
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.3
const EYE_OFFSET := -0.14
const CROUCH_TRANSITION_SPEED := 8.0

var yaw: float = 0.0
var pitch: float = 0.0
var crouching: bool = false
var crouch_amount: float = 0.0        # 0 = standing, 1 = fully crouched (visual/eye height)
var walking: bool = false
var on_ladder: bool = false
var ladder_dir: Vector3 = Vector3.FORWARD
var was_on_floor: bool = true
var fall_speed_peak: float = 0.0
var base_speed: float = 5.4           # set from the active weapon config
var footstep_distance: float = 0.0
var last_cmd_tick: int = 0
var noclip: bool = false
var frozen: bool = false              # freeze time: look allowed, no movement
var jump_was_held: bool = false

var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _ladders_inside: Array = []

signal landed(impact_speed: float)
signal footstep_taken(loud: bool)
signal jumped()


func _init() -> void:
	collision_layer = 2
	collision_mask = 1 | 4   # world, player blockers (railings)
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.3
	safe_margin = 0.01
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.36
	_capsule.height = STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position = Vector3(0, STAND_HEIGHT / 2.0, 0)
	add_child(_shape)


func eye_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount) + EYE_OFFSET


func eye_position() -> Vector3:
	return global_position + Vector3(0, eye_height(), 0)


func view_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func aim_direction() -> Vector3:
	return -view_basis().z


func current_max_speed() -> float:
	var s := base_speed
	if crouching:
		s *= CROUCH_MULT
	elif walking:
		s *= WALK_MULT
	return s


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func enter_ladder(ladder: Node) -> void:
	if not _ladders_inside.has(ladder):
		_ladders_inside.append(ladder)


func exit_ladder(ladder: Node) -> void:
	_ladders_inside.erase(ladder)


func simulate(cmd: InputCmd, dt: float) -> void:
	yaw = cmd.yaw
	pitch = clampf(cmd.pitch, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)
	last_cmd_tick = cmd.tick
	if noclip:
		_simulate_noclip(cmd, dt)
		return
	var want_crouch := cmd.has(InputCmd.BTN_CROUCH)
	if not want_crouch and crouching and not _can_stand():
		want_crouch = true
	crouching = want_crouch
	walking = cmd.has(InputCmd.BTN_WALK) and not crouching
	crouch_amount = move_toward(crouch_amount, 1.0 if crouching else 0.0, CROUCH_TRANSITION_SPEED * dt)
	_capsule.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount)
	_shape.position.y = _capsule.height / 2.0
	var move := cmd.move
	if frozen:
		move = Vector2.ZERO
	var wish_dir := (Basis(Vector3.UP, yaw) * Vector3(move.x, 0, -move.y))
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()
	on_ladder = not _ladders_inside.is_empty() and not is_on_floor_ladder_exit(move)
	if on_ladder:
		_simulate_ladder(cmd, wish_dir, dt)
	else:
		_simulate_walk(cmd, wish_dir, dt)
	move_and_slide()
	# landing / fall damage
	if is_on_floor() and not was_on_floor:
		landed.emit(fall_speed_peak)
		fall_speed_peak = 0.0
	if not is_on_floor():
		fall_speed_peak = max(fall_speed_peak, -velocity.y)
	was_on_floor = is_on_floor()
	# footsteps by distance travelled on ground
	if is_on_floor() or on_ladder:
		var hs: float = horizontal_speed() if not on_ladder else absf(velocity.y)
		footstep_distance += hs * dt
		var stride := 2.2 if not crouching else 1.6
		if footstep_distance >= stride and hs > 0.5:
			footstep_distance = 0.0
			footstep_taken.emit(not walking and not crouching)


func is_on_floor_ladder_exit(move: Vector2) -> bool:
	# leaving a ladder: on the floor and moving away from it
	return is_on_floor() and move.y < -0.1


func _simulate_walk(cmd: InputCmd, wish_dir: Vector3, dt: float) -> void:
	var max_speed := current_max_speed()
	var hvel := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor():
		# ground: friction then acceleration toward wish velocity
		var speed := hvel.length()
		if speed > 0.0:
			var drop := speed * GROUND_FRICTION * dt
			hvel *= max(speed - drop, 0.0) / speed
		var wish_vel := wish_dir * max_speed
		var accel := GROUND_ACCEL * dt
		var delta := wish_vel - hvel
		if delta.length() > accel:
			delta = delta.normalized() * accel
		hvel += delta
		velocity.y = 0.0
		var jump_pressed := cmd.has(InputCmd.BTN_JUMP)
		if jump_pressed and not jump_was_held and not frozen:
			velocity.y = JUMP_VELOCITY
			jumped.emit()
		jump_was_held = jump_pressed
	else:
		# air: limited acceleration (air strafing), gravity
		jump_was_held = cmd.has(InputCmd.BTN_JUMP)
		if wish_dir.length_squared() > 0.0:
			var wish_speed: float = min(max_speed, AIR_MAX_WISH)
			var current := hvel.dot(wish_dir)
			var add: float = wish_speed - current
			if add > 0.0:
				hvel += wish_dir * min(add, AIR_ACCEL * max_speed * dt)
		velocity.y -= GRAVITY * dt
	velocity.x = hvel.x
	velocity.z = hvel.z


func _simulate_ladder(cmd: InputCmd, wish_dir: Vector3, dt: float) -> void:
	var climb := 0.0
	var forward := -Basis(Vector3.UP, yaw).z
	var facing_ladder := forward.dot(ladder_dir) > -0.2
	# forward input climbs when looking at/along the ladder, descends when looking down steeply
	if cmd.move.y > 0.1:
		climb = 1.0 if (pitch > -0.5 or not facing_ladder) else -1.0
	elif cmd.move.y < -0.1:
		climb = -1.0
	var lateral := wish_dir - ladder_dir * wish_dir.dot(ladder_dir)
	velocity = Vector3(lateral.x * LADDER_SPEED * 0.5, climb * LADDER_SPEED, lateral.z * LADDER_SPEED * 0.5)
	if cmd.has(InputCmd.BTN_JUMP) and not jump_was_held:
		velocity = -ladder_dir * 3.5 + Vector3.UP * 2.5
		_ladders_inside.clear()
		on_ladder = false
	jump_was_held = cmd.has(InputCmd.BTN_JUMP)
	if is_on_floor() and climb < 0.0:
		_ladders_inside.clear()


func _simulate_noclip(cmd: InputCmd, dt: float) -> void:
	var dir := view_basis() * Vector3(cmd.move.x, 0, -cmd.move.y)
	if cmd.has(InputCmd.BTN_JUMP):
		dir.y += 1.0
	if cmd.has(InputCmd.BTN_CROUCH):
		dir.y -= 1.0
	var speed := 12.0 if not cmd.has(InputCmd.BTN_WALK) else 3.0
	global_position += dir * speed * dt
	velocity = Vector3.ZERO


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius - 0.02
	shape.height = STAND_HEIGHT
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT / 2.0 + 0.02, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


## Snapshot of the simulation state for prediction/reconciliation.
func get_state() -> Dictionary:
	return {
		"p": global_position, "v": velocity, "yaw": yaw, "pitch": pitch, "c": crouching, "ca": crouch_amount,
		"floor": was_on_floor, "ladder": on_ladder, "peak": fall_speed_peak, "jh": jump_was_held,
	}


func set_state(s: Dictionary) -> void:
	global_position = s.p
	velocity = s.v
	yaw = s.yaw
	pitch = s.pitch
	crouching = s.c
	crouch_amount = s.get("ca", 1.0 if s.c else 0.0)
	was_on_floor = s.get("floor", true)
	on_ladder = s.get("ladder", false)
	fall_speed_peak = s.get("peak", 0.0)
	jump_was_held = s.get("jh", false)
	_capsule.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount)
	_shape.position.y = _capsule.height / 2.0
