class_name Player
extends PlayerBody
## A player (human or bot). The server runs the authoritative simulation through process_cmd();
## the owning client runs the same function for prediction (authoritative = false) and remote
## clients only receive snapshots. Presentation nodes are created only where needed.

signal died(killer_id: int, weapon_id: String, headshot: bool)
signal damaged(amount: int, attacker_id: int, zone: int)
signal shot_fired(weapon_id: String, origin: Vector3, direction: Vector3, impact: Vector3, impact_kind: int)

const IMPACT_NONE := 0
const IMPACT_WORLD := 1
const IMPACT_PLAYER := 2
const IMPACT_HEADSHOT := 3

var peer_id: int = 0
var player_name: String = "Player"
var team: int = Teams.NONE
var is_bot: bool = false
var is_local: bool = false

var health: int = 100
var armor: int = 0
var has_helmet: bool = false
var money: int = 800
var alive: bool = false
var inventory := Inventory.new()
var active_slot: int = Inventory.SLOT_SECONDARY
var previous_slot: int = Inventory.SLOT_MELEE
var recoil_offset: Vector2 = Vector2.ZERO      # degrees (yaw, pitch) currently applied to the aim
var zoomed: bool = false
var throw_timer: float = -1.0
var throw_alt: bool = false
var melee_timer: float = -1.0
var melee_heavy: bool = false
var plant_progress: float = 0.0
var defuse_progress: float = 0.0
var planting: bool = false
var defusing: bool = false
var flash_end: float = 0.0                     # server-side (bots); clients get Events.flashed
var burn_timer: float = 0.0
var last_attacker_id: int = 0
var damage_log: Dictionary = {}                # attacker_id -> {"damage": int, "time": float}
var stats := {"kills": 0, "deaths": 0, "assists": 0, "score": 0, "mvps": 0, "damage": 0, "headshots": 0}
var prev_buttons: int = 0
var spawn_time: float = 0.0
var disconnected: bool = false
var death_time: float = 0.0
var look_pickup: Node = null                   # WeaponPickup the player is looking at (server)
var rng := RandomNumberGenerator.new()

# presentation
var camera: Camera3D
var head: Node3D
var view_model: Node3D
var model: Node3D
var name_label: Label3D


func _init() -> void:
	super()
	rules_ready()


func rules_ready() -> void:
	pass


func setup(id: int, pname: String, t: int, bot: bool) -> void:
	peer_id = id
	player_name = pname
	team = t
	is_bot = bot
	name = "Player_%d" % id


func active_weapon() -> WeaponState:
	return inventory.get_active(active_slot)


func active_config() -> WeaponConfig:
	var w := active_weapon()
	return w.cfg if w else null


func is_alive() -> bool:
	return alive


# ------------------------------------------------------------------------------ spawning
func spawn_at(pos: Vector3, spawn_yaw: float, rules: MatchRules) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = spawn_yaw
	pitch = 0.0
	health = rules.max_health
	alive = true
	crouching = false
	crouch_amount = 0.0
	recoil_offset = Vector2.ZERO
	plant_progress = 0.0
	defuse_progress = 0.0
	planting = false
	defusing = false
	throw_timer = -1.0
	melee_timer = -1.0
	burn_timer = 0.0
	zoomed = false
	damage_log.clear()
	last_attacker_id = 0
	spawn_time = Time.get_ticks_msec() / 1000.0
	collision_layer = 2
	set_state(get_state())
	if not inventory.has_slot(Inventory.SLOT_MELEE):
		inventory.give(WeaponDB.get_config("knife"))
	active_slot = inventory.best_slot()
	var w := active_weapon()
	if w:
		w.on_equip()
	if model:
		model.set_alive(true)
	Events.player_spawned.emit(peer_id)


func full_reset_inventory() -> void:
	inventory.reset_to_default(team)
	armor = 0
	has_helmet = false
	active_slot = Inventory.SLOT_SECONDARY


# ------------------------------------------------------------------------------ simulation
func process_cmd(cmd: InputCmd, dt: float, authoritative: bool) -> void:
	if not alive:
		return
	var just := cmd.buttons & ~prev_buttons
	prev_buttons = cmd.buttons
	_handle_slot_change(cmd, just)
	var w := active_weapon()
	base_speed = w.cfg.move_speed if w else 5.4
	if zoomed:
		base_speed *= 0.6
	if planting or defusing:
		base_speed = 0.0
	simulate(cmd, dt)
	_decay_recoil(dt)
	if w == null:
		return
	for ev in w.tick(dt):
		match ev:
			"burst_shot":
				_fire_shot(cmd, w, authoritative)
			"reloaded":
				pass
	var fire_held := cmd.has(InputCmd.BTN_FIRE)
	var fire_just := (just & InputCmd.BTN_FIRE) != 0
	var alt_just := (just & InputCmd.BTN_ALT_FIRE) != 0
	if w.cfg.is_firearm():
		if not (planting or defusing) and w.try_fire(fire_held, fire_just):
			_fire_shot(cmd, w, authoritative)
		if alt_just and not w.cfg.zoom_levels.is_empty() and not w.is_busy():
			_cycle_zoom(w)
		if (just & InputCmd.BTN_RELOAD) != 0 and w.start_reload():
			zoomed = false
		elif w.ammo == 0 and w.reserve > 0 and not w.is_busy() and fire_just and w.can_reload():
			w.start_reload()
	elif w.cfg.category == "melee":
		if melee_timer >= 0.0:
			melee_timer -= dt
			if melee_timer < 0.0:
				_melee_hit(cmd, w, authoritative)
		elif not w.is_busy() and w.next_fire_time <= 0.0 and (fire_just or alt_just):
			melee_heavy = alt_just
			melee_timer = 0.12 if not melee_heavy else 0.35
			w.next_fire_time = 0.45 if not melee_heavy else w.cfg.melee_heavy_delay
			shot_fired.emit(w.cfg.id, eye_position(), aim_direction(), Vector3.ZERO, IMPACT_NONE)
	elif w.cfg.category == "grenade":
		if throw_timer >= 0.0:
			throw_timer -= dt
			if throw_timer < 0.0:
				_throw_grenade(cmd, w, authoritative)
		elif not w.is_busy() and (fire_just or alt_just):
			throw_alt = alt_just
			throw_timer = 0.22
			shot_fired.emit(w.cfg.id, eye_position(), aim_direction(), Vector3.ZERO, IMPACT_NONE)
	if (just & InputCmd.BTN_INSPECT) != 0:
		w.start_inspect()
	if authoritative:
		_server_use(cmd, dt, just)
		_server_burn(dt)
		if (just & InputCmd.BTN_DROP) != 0:
			Net.server_drop_weapon(self, active_slot)


func _handle_slot_change(cmd: InputCmd, just: int) -> void:
	var target := -1
	if cmd.weapon_slot >= 0 and cmd.weapon_slot != active_slot:
		target = cmd.weapon_slot
	elif (just & InputCmd.BTN_QUICK_SWITCH) != 0:
		target = previous_slot
	if target < 0 or not inventory.has_slot(target):
		return
	if planting or defusing:
		return
	var old := active_weapon()
	if old:
		old.on_holster()
	previous_slot = active_slot
	active_slot = target
	zoomed = false
	throw_timer = -1.0
	melee_timer = -1.0
	var w := active_weapon()
	if w:
		w.on_equip()


func switch_to_slot(slot: int) -> void:
	if inventory.has_slot(slot) and slot != active_slot:
		var old := active_weapon()
		if old:
			old.on_holster()
		previous_slot = active_slot
		active_slot = slot
		zoomed = false
		var w := active_weapon()
		if w:
			w.on_equip()


func _cycle_zoom(w: WeaponState) -> void:
	var levels := w.cfg.zoom_levels.size()
	if not zoomed:
		zoomed = true
		w.zoom_level = 0
	elif w.zoom_level + 1 < levels:
		w.zoom_level += 1
	else:
		zoomed = false
		w.zoom_level = 0


func _decay_recoil(dt: float) -> void:
	var w := active_weapon()
	if w == null or recoil_offset == Vector2.ZERO:
		return
	var rate: float = (w.cfg.recoil_magnitude * 6.0) / max(w.cfg.recoil_recovery_time, 0.05)
	recoil_offset = recoil_offset.move_toward(Vector2.ZERO, rate * dt)


func aim_with_recoil() -> Vector3:
	var b := Basis(Vector3.UP, yaw - deg_to_rad(recoil_offset.x)) * Basis(Vector3.RIGHT, pitch + deg_to_rad(recoil_offset.y))
	return -b.z


## Deterministic spread direction for pellet `index` of the shot fired at `tick`.
func spread_direction(base_dir: Vector3, cone_deg: float, tick: int, index: int) -> Vector3:
	rng.seed = hash([peer_id, tick, index])
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * deg_to_rad(cone_deg)
	var right := base_dir.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := right.cross(base_dir).normalized()
	return (base_dir + (right * cos(a) + up * sin(a)) * tan(r)).normalized()


func _fire_shot(cmd: InputCmd, w: WeaponState, authoritative: bool) -> void:
	var kick := w.recoil_for_shot(w.consecutive_shots - 1)
	recoil_offset += kick
	var origin := eye_position()
	var base_dir := aim_with_recoil()
	var cone := w.inaccuracy(horizontal_speed(), crouching, not is_on_floor(), on_ladder, zoomed)
	for i in range(w.cfg.pellets):
		var dir := spread_direction(base_dir, cone, cmd.tick, i)
		if authoritative:
			Net.server_resolve_shot(self, w.cfg, origin, dir, cmd.view_tick, cmd.tick, i)
		else:
			# prediction: visual impact only
			var hit := _visual_trace(origin, dir, w.cfg.max_range)
			shot_fired.emit(w.cfg.id, origin, dir, hit.get("point", origin + dir * w.cfg.max_range), hit.get("kind", IMPACT_NONE))
	if w.cfg.fire_mode == WeaponConfig.FireMode.BOLT or w.cfg.fire_mode == WeaponConfig.FireMode.PUMP:
		zoomed = false


func _visual_trace(origin: Vector3, dir: Vector3, max_range: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, 1 | 2)
	q.exclude = [get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return {}
	var kind := IMPACT_PLAYER if r.collider is Player else IMPACT_WORLD
	return {"point": r.position, "normal": r.normal, "kind": kind, "collider": r.collider}


func _melee_hit(cmd: InputCmd, w: WeaponState, authoritative: bool) -> void:
	if authoritative:
		Net.server_resolve_melee(self, w.cfg, eye_position(), aim_direction(), melee_heavy, cmd.view_tick)


func _throw_grenade(cmd: InputCmd, w: WeaponState, authoritative: bool) -> void:
	if authoritative:
		var speed := w.cfg.throw_speed * (0.45 if throw_alt else 1.0)
		var dir := (aim_direction() + Vector3.UP * 0.12).normalized()
		Net.server_throw_grenade(self, w.cfg, eye_position() + dir * 0.3, dir * speed + velocity * 0.5)
		inventory.remove(Inventory.SLOT_GRENADE, w.cfg.id)
		if not inventory.has_slot(Inventory.SLOT_GRENADE):
			switch_to_slot(inventory.best_slot())
		else:
			active_weapon().on_equip()
		Net.server_sync_inventory(self)
	else:
		w.equip_timer = 0.5


# ------------------------------------------------------------------------------ server: use / objective
func _server_use(cmd: InputCmd, dt: float, just: int) -> void:
	var use_held := cmd.has(InputCmd.BTN_USE)
	var m := Match
	if team == Teams.ATTACKERS and inventory.has_bomb() and active_slot == Inventory.SLOT_BOMB:
		var site: String = m.site_at(global_position)
		if use_held and site != "" and is_on_floor() and m.can_plant():
			planting = true
			plant_progress += dt / m.rules.plant_time
			if plant_progress >= 1.0:
				planting = false
				plant_progress = 0.0
				m.server_plant_bomb(self, site)
				Net.server_sync_inventory(self)
		else:
			planting = false
			plant_progress = 0.0
	elif team == Teams.DEFENDERS and m.bomb_planted():
		var near: bool = m.bomb_position.distance_to(global_position) < 1.8
		var looking: bool = aim_direction().dot((m.bomb_position - eye_position()).normalized()) > 0.3
		if use_held and near and (looking or defusing) and is_on_floor():
			defusing = true
			var t: float = m.rules.kit_defuse_time if inventory.has_kit else m.rules.defuse_time
			defuse_progress += dt / t
			if defuse_progress >= 1.0:
				m.server_defuse_bomb(self)
				defusing = false
				defuse_progress = 0.0
		else:
			defusing = false
			defuse_progress = 0.0
	else:
		planting = false
		defusing = false
		plant_progress = 0.0
		defuse_progress = 0.0
	if (just & InputCmd.BTN_USE) != 0 and not planting and not defusing:
		Net.server_try_pickup_swap(self)


func _server_burn(dt: float) -> void:
	if burn_timer > 0.0:
		burn_timer -= dt


# ------------------------------------------------------------------------------ server: damage
func server_apply_damage(amount: int, armor_damage: int, attacker_id: int, weapon_id: String, zone: int, from_dir: Vector3, armor_hit: bool) -> bool:
	if not alive or amount <= 0:
		return false
	health -= amount
	if armor_hit:
		armor = maxi(armor - armor_damage, 0)
	last_attacker_id = attacker_id
	if attacker_id != peer_id and attacker_id != 0:
		var entry: Dictionary = damage_log.get(attacker_id, {"damage": 0, "time": 0.0})
		entry.damage += amount
		entry.time = Time.get_ticks_msec() / 1000.0
		damage_log[attacker_id] = entry
	damaged.emit(amount, attacker_id, zone)
	Net.server_broadcast_damage(self, attacker_id, amount, zone, from_dir, armor_hit)
	if health <= 0:
		health = 0
		server_die(attacker_id, weapon_id, zone == DamageModel.Zone.HEAD)
		return true
	return false


func server_die(killer_id: int, weapon_id: String, headshot: bool) -> void:
	if not alive:
		return
	alive = false
	death_time = Time.get_ticks_msec() / 1000.0
	planting = false
	defusing = false
	plant_progress = 0.0
	defuse_progress = 0.0
	zoomed = false
	collision_layer = 0
	velocity = Vector3.ZERO
	stats.deaths += 1
	var assist := 0
	var best := 0
	for aid in damage_log:
		if aid != killer_id and damage_log[aid].damage > best and damage_log[aid].damage >= 40:
			best = damage_log[aid].damage
			assist = aid
	died.emit(killer_id, weapon_id, headshot)
	Net.server_on_player_died(self, killer_id, weapon_id, headshot, assist)
	if model:
		model.set_alive(false)


# ------------------------------------------------------------------------------ presentation
func setup_visuals(local: bool) -> void:
	is_local = local
	if DisplayServer.get_name() == "headless":
		return
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	if local:
		camera = Camera3D.new()
		camera.name = "Camera"
		camera.fov = Settings.fov()
		camera.near = 0.02
		camera.far = 400.0
		head.add_child(camera)
		var vm_script := load("res://src/player/ViewModel.gd")
		view_model = vm_script.new()
		view_model.name = "ViewModel"
		camera.add_child(view_model)
		view_model.setup(self)
	var model_script := load("res://src/player/PlayerModel.gd")
	model = model_script.new()
	model.name = "Model"
	add_child(model)
	model.setup(self)
	model.visible = not local
	if not local:
		name_label = Label3D.new()
		name_label.text = player_name
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.font_size = 28
		name_label.position = Vector3(0, 2.05, 0)
		name_label.no_depth_test = false
		name_label.visible = false
		add_child(name_label)


func _process(delta: float) -> void:
	if head == null:
		return
	head.position.y = eye_height()
	if is_local and camera:
		var cam_yaw := yaw - deg_to_rad(recoil_offset.x) * active_camera_ratio()
		var cam_pitch := pitch + deg_to_rad(recoil_offset.y) * active_camera_ratio()
		head.rotation = Vector3(0, cam_yaw, 0)
		camera.rotation = Vector3(cam_pitch, 0, 0)
	else:
		head.rotation = Vector3(0, yaw, 0)
	if model:
		model.update_pose(delta)
	if name_label:
		var lp := Net.local_player()
		name_label.visible = lp != null and lp.team == team and alive


func active_camera_ratio() -> float:
	var w := active_weapon()
	return w.cfg.recoil_camera_ratio if w else 0.5


func snapshot_state() -> Dictionary:
	var w := active_weapon()
	return {
		"id": peer_id, "p": global_position, "v": velocity, "yaw": yaw, "pitch": pitch,
		"alive": alive, "crouch": crouch_amount, "ladder": on_ladder, "floor": was_on_floor,
		"hp": health, "armor": armor, "weapon": w.cfg.id if w else "", "reloading": w.reload_timer >= 0.0 if w else false,
		"plant": plant_progress if planting else 0.0, "defuse": defuse_progress if defusing else 0.0,
		"ammo": w.ammo if w else 0, "reserve": w.reserve if w else 0, "zoomed": zoomed, "slot": active_slot,
		"helmet": has_helmet, "kit": inventory.has_kit, "bomb": inventory.has_bomb(), "tick": last_cmd_tick,
		"recoil": recoil_offset,
	}
