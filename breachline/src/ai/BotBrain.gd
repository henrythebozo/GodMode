extends Node
## Bot AI: a finite-state machine producing InputCmds every server tick, navigating with the map
## navmesh through a NavigationAgent3D. States are documented on the enum.

enum S {
	BUY,          # freeze time: purchase loadout, wait
	ROAM,         # warmup / no objective: wander between patrol points
	PUSH,         # attackers: move to the chosen bomb site (escort the carrier)
	DEFEND,       # hold a cover point near a site / the planted bomb
	INVESTIGATE,  # go look at a recent enemy noise
	ENGAGE,       # enemy visible: aim, fire, strafe
	SEEK_COVER,   # low health / reloading under fire: move to nearest cover
	PLANT,        # carrier at site: plant
	RETAKE,       # defenders after plant: move to the bomb
	DEFUSE,       # at the bomb, no enemies in sight: defuse
	FETCH_BOMB,   # attackers: pick up a dropped bomb
}

const PROFILES := [
	{"reaction": 0.75, "aim_error": 5.0, "turn": 3.5, "vision": 35.0, "fov": 90.0, "burst": 3, "nade": 0.15, "accuracy_hold": 0.45},
	{"reaction": 0.42, "aim_error": 2.6, "turn": 6.0, "vision": 55.0, "fov": 110.0, "burst": 5, "nade": 0.35, "accuracy_hold": 0.3},
	{"reaction": 0.22, "aim_error": 1.3, "turn": 10.0, "vision": 75.0, "fov": 130.0, "burst": 8, "nade": 0.55, "accuracy_hold": 0.18},
	{"reaction": 0.10, "aim_error": 0.6, "turn": 16.0, "vision": 100.0, "fov": 150.0, "burst": 12, "nade": 0.75, "accuracy_hold": 0.1},
]

var player: Player
var profile: Dictionary = PROFILES[1]
var difficulty := 1
var state: int = S.ROAM
var nav: NavigationAgent3D
var target: Player
var target_seen_time := 0.0
var last_seen_pos := Vector3.ZERO
var noticed_time := -1.0
var yaw := 0.0
var pitch := 0.0
var desired_yaw := 0.0
var desired_pitch := 0.0
var goal := Vector3.ZERO
var goal_reason := ""
var chosen_site := ""
var think_timer := 0.0
var perception_timer := 0.0
var stuck_timer := 0.0
var last_pos := Vector3.ZERO
var strafe_dir := 1.0
var strafe_timer := 0.0
var fire_timer := 0.0
var burst_left := 0
var bought_this_round := -1
var crouch_hold := 0.0
var rng := RandomNumberGenerator.new()
var nade_cooldown := 0.0
var investigate_pos := Vector3.ZERO
var cover_pos := Vector3.ZERO
var hold_time := 0.0
var aim_noise := Vector2.ZERO
var noise_timer := 0.0
var slot_request := -1
var jump_timer := 0.0


func setup(p: Player, diff: int) -> void:
	player = p
	rng.seed = hash(p.peer_id) + Time.get_ticks_usec()
	set_difficulty(diff)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.0
	nav.radius = 0.45
	nav.height = 1.8
	nav.path_max_distance = 3.0
	nav.avoidance_enabled = false
	p.add_child(nav)
	yaw = p.yaw


func set_difficulty(d: int) -> void:
	difficulty = clampi(d, 0, PROFILES.size() - 1)
	profile = PROFILES[difficulty]


func state_name() -> String:
	return S.keys()[state]


# ---------------------------------------------------------------------------- main loop
func think(dt: float, tick: int) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.tick = tick
	cmd.view_tick = tick
	var p := player
	if not p.alive:
		state = S.ROAM
		target = null
		cmd.yaw = p.yaw
		cmd.pitch = p.pitch
		return cmd
	perception_timer -= dt
	if perception_timer <= 0.0:
		perception_timer = 0.08
		_perceive()
	think_timer -= dt
	if think_timer <= 0.0:
		think_timer = 0.25
		_decide()
	nade_cooldown -= dt
	_act(cmd, dt)
	cmd.yaw = yaw
	cmd.pitch = pitch
	return cmd


# ---------------------------------------------------------------------------- perception
func _can_see(other: Player) -> bool:
	var eye := player.eye_position()
	var to := other.eye_position() - eye
	var dist := to.length()
	if dist > profile.vision:
		return false
	var forward := player.aim_direction()
	if forward.angle_to(to.normalized()) > deg_to_rad(profile.fov * 0.5):
		return false
	var space := player.get_world_3d().direct_space_state
	for target_point in [other.eye_position(), other.global_position + Vector3(0, 0.9, 0)]:
		var q := PhysicsRayQueryParameters3D.create(eye, target_point, 1)
		if space.intersect_ray(q).is_empty():
			# smoke check
			var blocked := false
			for e in Net.entities.values():
				if e is AreaEffect and e.blocks_sight(eye, target_point):
					blocked = true
					break
			if not blocked:
				return true
	return false


func _perceive() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if player.flash_end > now:
		target = null
		return
	var best: Player = null
	var best_d := INF
	for other: Player in Net.players.values():
		if other == player or not other.alive or other.team == player.team:
			continue
		var d := player.global_position.distance_to(other.global_position)
		if d < best_d and _can_see(other):
			best = other
			best_d = d
	if best:
		if target != best:
			noticed_time = now
		target = best
		target_seen_time = now
		last_seen_pos = best.global_position
	elif target and now - target_seen_time > 2.5:
		target = null
	# noises from enemies
	for n in Match.noise_events:
		if n.team != player.team and now - n.time < 0.5 and n.pos.distance_to(player.global_position) < (40.0 if n.kind == "gunfire" else 18.0):
			if state in [S.ROAM, S.DEFEND, S.PUSH] and rng.randf() < 0.5:
				investigate_pos = n.pos
				if state != S.ENGAGE:
					_set_state(S.INVESTIGATE)


# ---------------------------------------------------------------------------- decision
func _set_state(s: int) -> void:
	if state != s:
		state = s
		hold_time = 0.0


func _decide() -> void:
	var p := player
	var m := Match
	var now := Time.get_ticks_msec() / 1000.0
	# buy phase
	if m.state == m.State.FREEZE or (m.state == m.State.LIVE and m.buy_time_left > 0.0 and bought_this_round != m.round_number):
		if bought_this_round != m.round_number and m.in_buy_zone(p):
			_buy()
			bought_this_round = m.round_number
		if m.state == m.State.FREEZE:
			_set_state(S.BUY)
			return
	if target:
		if state != S.ENGAGE:
			_set_state(S.ENGAGE)
		return
	if state == S.ENGAGE and target == null:
		investigate_pos = last_seen_pos
		_set_state(S.INVESTIGATE)
		return
	if state == S.SEEK_COVER and hold_time > 2.5:
		_set_state(S.ROAM)
	if m.state == m.State.WARMUP or m.state == m.State.LOBBY:
		if state != S.INVESTIGATE:
			_set_state(S.ROAM)
		return
	if m.state != m.State.LIVE and m.state != m.State.PLANTED:
		_set_state(S.ROAM)
		return
	if p.team == Teams.ATTACKERS:
		if m.bomb_state == "dropped" and state != S.FETCH_BOMB and _closest_teammate_to(m.bomb_position) == p:
			_set_state(S.FETCH_BOMB)
			return
		if m.bomb_state == "planted":
			_set_state(S.DEFEND)
			return
		if state in [S.INVESTIGATE, S.FETCH_BOMB]:
			if state == S.FETCH_BOMB and m.bomb_state != "dropped":
				_set_state(S.PUSH)
			return
		if p.inventory.has_bomb():
			if m.site_at(p.global_position) != "" and m.can_plant():
				_set_state(S.PLANT)
				return
			_set_state(S.PUSH)
			return
		if m.site_at(p.global_position) != "" and m.site_at(p.global_position) == chosen_site and hold_time < 25.0:
			_set_state(S.DEFEND)
			return
		_set_state(S.PUSH)
	else:
		if m.bomb_state == "planted":
			var d := p.global_position.distance_to(m.bomb_position)
			if d < 1.6:
				_set_state(S.DEFUSE)
			else:
				_set_state(S.RETAKE)
			return
		if state == S.INVESTIGATE:
			return
		if m.time_left < 35.0 and state == S.DEFEND and rng.randf() < 0.3:
			# late round: push out to find the attackers
			_set_state(S.INVESTIGATE)
			investigate_pos = _random_patrol_point()
			return
		_set_state(S.DEFEND)


func _closest_teammate_to(pos: Vector3) -> Player:
	var best: Player = null
	var bd := INF
	for o: Player in Net.players.values():
		if o.team == player.team and o.alive:
			var d: float = o.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = o
	return best


func _buy() -> void:
	var p := player
	var m := Match
	var team := p.team
	var money := p.money
	var rifle := "corsair" if team == Teams.ATTACKERS else "lynx"
	if not p.inventory.has_slot(Inventory.SLOT_PRIMARY):
		if money >= 5900 and difficulty >= 2 and rng.randf() < 0.3:
			m.server_buy(p.peer_id, "longbow")
		elif money >= WeaponDB.get_config(rifle).price + 1000:
			m.server_buy(p.peer_id, rifle)
		elif money >= 3200 and rng.randf() < 0.5:
			m.server_buy(p.peer_id, "falcon" if team == Teams.DEFENDERS else "raptor")
		elif money >= 2400:
			m.server_buy(p.peer_id, "bulldog" if rng.randf() < 0.5 else "viper")
		elif money >= 1500:
			m.server_buy(p.peer_id, "reed" if rng.randf() < 0.6 else "breaker")
	money = p.money
	if p.armor <= 0 and money >= 1000:
		m.server_buy(p.peer_id, "helmet" if money >= 1400 else "armor")
	money = p.money
	if team == Teams.DEFENDERS and not p.inventory.has_kit and money >= 900:
		m.server_buy(p.peer_id, "defuse_kit")
	money = p.money
	if money >= 900 and p.inventory.get_active(Inventory.SLOT_SECONDARY) and p.inventory.get_active(Inventory.SLOT_SECONDARY).cfg.id == "p9" and rng.randf() < 0.3:
		m.server_buy(p.peer_id, "kestrel")
	for nade in ["smoke", "flash", "frag", "flash"]:
		if p.money >= 700 and rng.randf() < 0.7:
			m.server_buy(p.peer_id, nade)


func _random_patrol_point() -> Vector3:
	var pts: Array = Match.layout.get("patrol_points", [])
	if pts.is_empty():
		return player.global_position
	var pt: Dictionary = pts[rng.randi() % pts.size()]
	return Vector3(pt.pos[0], pt.pos[1], pt.pos[2])


func _site_pos(site: String) -> Vector3:
	var s: Dictionary = Match.layout.get("sites", {}).get(site, {})
	if s.is_empty():
		return player.global_position
	var c := Vector3(s.pos[0], s.pos[1], s.pos[2])
	return c + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))


func _choose_site() -> String:
	if chosen_site != "":
		return chosen_site
	# attackers agree on a site per round by hashing the round number with a shared seed
	var sites: Array = Match.layout.get("sites", {}).keys()
	if sites.is_empty():
		return ""
	sites.sort()
	var idx := (Match.round_number * 7 + int(Match.rules.max_rounds)) % sites.size()
	chosen_site = sites[idx] if player.team == Teams.ATTACKERS else sites[rng.randi() % sites.size()]
	return chosen_site


func _nearest_cover(from: Vector3, threat: Vector3) -> Vector3:
	var best := from
	var bd := INF
	for c in Match.layout.get("cover", []):
		var pos := Vector3(c.pos[0], c.pos[1], c.pos[2])
		var cover_dir := Vector3(c.cover_dir[0], 0, c.cover_dir[2])
		var d := from.distance_to(pos)
		if d > 20.0:
			continue
		# cover must be between us and the threat
		var to_threat := (threat - pos)
		to_threat.y = 0
		if to_threat.normalized().dot(cover_dir) < 0.3:
			continue
		if d < bd:
			bd = d
			best = pos
	return best


# ---------------------------------------------------------------------------- acting
func _act(cmd: InputCmd, dt: float) -> void:
	var p := player
	var m := Match
	var now := Time.get_ticks_msec() / 1000.0
	var move_target := Vector3.INF
	var look_target := Vector3.INF
	var want_fire := false
	var want_crouch := false
	var want_use := false
	var want_walk := false
	hold_time += dt
	match state:
		S.BUY:
			look_target = p.global_position + Basis(Vector3.UP, p.yaw) * Vector3.FORWARD * 5.0
			chosen_site = ""
			_prefer_best_weapon()
		S.ROAM:
			if goal == Vector3.ZERO or p.global_position.distance_to(goal) < 2.0 or hold_time > 20.0:
				goal = _random_patrol_point()
				hold_time = 0.0
			move_target = goal
		S.PUSH:
			var site := _choose_site()
			if goal_reason != "site" or hold_time > 30.0:
				goal = _site_pos(site)
				goal_reason = "site"
			move_target = goal
			_maybe_throw_grenade(cmd, move_target)
			if p.global_position.distance_to(goal) < 3.0:
				hold_time = 0.0
				_set_state(S.DEFEND)
		S.DEFEND:
			if goal_reason != "defend" or hold_time > 25.0:
				var anchor: Vector3 = m.bomb_position if m.bomb_state == "planted" else _site_pos(_choose_site())
				var cover := _nearest_cover(anchor, anchor + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 20.0)
				goal = cover if cover != anchor else anchor
				goal_reason = "defend"
				hold_time = 0.0
			if p.global_position.distance_to(goal) > 1.2:
				move_target = goal
			else:
				# look toward the map centre / likely approach, crouch sometimes
				var centre := Vector3(m.layout.get("size", [120, 100])[0] * 0.5, 0, m.layout.get("size", [120, 100])[1] * 0.5)
				look_target = centre + Vector3(sin(now * 0.3) * 10.0, 1.5, cos(now * 0.3) * 10.0)
				want_crouch = difficulty >= 1 and fmod(hold_time, 8.0) < 3.0
		S.INVESTIGATE:
			move_target = investigate_pos
			want_walk = difficulty >= 2
			if p.global_position.distance_to(investigate_pos) < 2.0 or hold_time > 12.0:
				_set_state(S.ROAM if m.state != m.State.LIVE else (S.PUSH if p.team == Teams.ATTACKERS else S.DEFEND))
		S.ENGAGE:
			if target:
				look_target = target.eye_position() if difficulty >= 2 else target.global_position + Vector3(0, 1.2, 0)
				var dist := p.global_position.distance_to(target.global_position)
				var w := p.active_weapon()
				if w and w.cfg.category in ["melee", "grenade"]:
					_prefer_best_weapon()
				elif w and w.cfg.is_firearm() and w.ammo == 0 and w.reserve > 0:
					cmd.buttons |= InputCmd.BTN_RELOAD
					if difficulty >= 1:
						cover_pos = _nearest_cover(p.global_position, target.global_position)
						move_target = cover_pos
				var aim_err := _aim_error_to(look_target)
				var reacted: bool = now - noticed_time >= float(profile.reaction)
				if reacted and aim_err < deg_to_rad(4.0 + profile.aim_error):
					if fire_timer <= 0.0:
						if burst_left <= 0:
							burst_left = profile.burst
							fire_timer = 0.25 + (0.35 if dist > 25.0 else 0.0) * (1.0 if difficulty < 3 else 0.4)
						want_fire = true
						burst_left -= 1
					want_crouch = dist > 18.0 and difficulty >= 1 and w and w.cfg.category != "sniper"
				fire_timer -= dt
				# strafe while fighting at close range
				strafe_timer -= dt
				if strafe_timer <= 0.0:
					strafe_timer = rng.randf_range(0.5, 1.4)
					strafe_dir = -strafe_dir if rng.randf() < 0.7 else 0.0
				# a fight that stalls (nobody dying) turns into a push: close the distance
				if hold_time > 4.0 and dist > 7.0 and move_target == Vector3.INF and (p.team == Teams.ATTACKERS or hold_time > 9.0):
					move_target = target.global_position
					want_crouch = false
				if dist < 22.0 and move_target == Vector3.INF and not want_crouch:
					cmd.move.x = strafe_dir
				if p.health < 35 and difficulty >= 1 and rng.randf() < 0.02:
					cover_pos = _nearest_cover(p.global_position, target.global_position)
					_set_state(S.SEEK_COVER)
			else:
				look_target = last_seen_pos + Vector3(0, 1.5, 0)
		S.SEEK_COVER:
			move_target = cover_pos
			if target:
				look_target = target.eye_position()
			if p.global_position.distance_to(cover_pos) < 1.0:
				want_crouch = true
				var w := p.active_weapon()
				if w and w.ammo < w.cfg.mag_size / 3:
					cmd.buttons |= InputCmd.BTN_RELOAD
		S.PLANT:
			if p.active_slot != Inventory.SLOT_BOMB:
				slot_request = Inventory.SLOT_BOMB
			want_use = true
			want_crouch = true
			look_target = p.global_position + Vector3(0, 0.3, 0) + p.aim_direction() * Vector3(1, 0, 1) * 2.0
			if m.site_at(p.global_position) == "" or not p.inventory.has_bomb():
				_set_state(S.PUSH)
		S.RETAKE:
			move_target = m.bomb_position
			_maybe_throw_grenade(cmd, move_target)
		S.DEFUSE:
			look_target = m.bomb_position + Vector3(0, 0.1, 0)
			want_use = true
			want_crouch = true
			if m.bomb_state != "planted":
				_set_state(S.DEFEND)
		S.FETCH_BOMB:
			move_target = m.bomb_position
			if m.bomb_state != "dropped":
				_set_state(S.PUSH)
	# navigation
	if move_target != Vector3.INF:
		_navigate(cmd, move_target, dt)
		if look_target == Vector3.INF:
			var next := nav.get_next_path_position() if nav.is_navigation_finished() == false else move_target
			var dir := next - p.global_position
			if dir.length() > 0.5:
				look_target = p.eye_position() + Vector3(dir.x, 0, dir.z).normalized() * 10.0 + Vector3(0, 0.0, 0)
	else:
		nav.target_position = p.global_position
		if state != S.ENGAGE:
			cmd.move = Vector2.ZERO
	_aim(look_target, dt)
	if want_fire:
		cmd.buttons |= InputCmd.BTN_FIRE
	if want_crouch:
		cmd.buttons |= InputCmd.BTN_CROUCH
	if want_use:
		cmd.buttons |= InputCmd.BTN_USE
	if want_walk:
		cmd.buttons |= InputCmd.BTN_WALK
	if slot_request >= 0:
		cmd.weapon_slot = slot_request
		slot_request = -1
	# auto reload when safe
	var w := p.active_weapon()
	if w and w.cfg.is_firearm() and target == null and w.ammo < w.cfg.mag_size * 0.4 and w.reserve > 0 and not w.is_busy():
		cmd.buttons |= InputCmd.BTN_RELOAD
	# stuck detection: intending to move at full speed but barely moving
	if move_target != Vector3.INF and cmd.move.length() > 0.5 and not want_crouch and not want_walk and state != S.ENGAGE:
		if p.global_position.distance_to(last_pos) < 0.3 * dt * 64.0 / 64.0:
			stuck_timer += dt
		else:
			stuck_timer = 0.0
		if stuck_timer > 1.5:
			cmd.move.x = strafe_dir if strafe_dir != 0.0 else 1.0
			if stuck_timer > 2.2 and p.is_on_floor():
				cmd.buttons |= InputCmd.BTN_JUMP
			if stuck_timer > 4.0:
				stuck_timer = 0.0
				goal = _random_patrol_point()
				goal_reason = ""
	else:
		stuck_timer = 0.0
	last_pos = p.global_position


func _prefer_best_weapon() -> void:
	var best := player.inventory.best_slot()
	if player.active_slot != best and player.inventory.has_slot(best):
		slot_request = best


func _navigate(cmd: InputCmd, target_pos: Vector3, dt: float) -> void:
	var map_rid := player.get_world_3d().navigation_map
	var closest := NavigationServer3D.map_get_closest_point(map_rid, player.global_position)
	var dir: Vector3
	var next: Vector3 = target_pos
	if closest.distance_to(player.global_position) > 0.6:
		# standing on a prop or otherwise off the navmesh: walk back onto it first
		dir = closest - player.global_position
		if Vector2(dir.x, dir.z).length() < 0.25:
			dir = target_pos - player.global_position
	else:
		if nav.target_position.distance_to(target_pos) > 1.0:
			nav.target_position = target_pos
		if nav.is_navigation_finished():
			if player.global_position.distance_to(target_pos) < 2.5:
				return
			dir = target_pos - player.global_position   # unreachable goal: head straight for it
		else:
			next = nav.get_next_path_position()
			dir = next - player.global_position
	dir.y = 0.0
	if dir.length() < 0.2:
		return
	dir = dir.normalized()
	# express as local move axes relative to current yaw
	var basis := Basis(Vector3.UP, yaw)
	var local := basis.inverse() * dir
	cmd.move = Vector2(local.x, -local.z)
	if cmd.move.length() > 1.0:
		cmd.move = cmd.move.normalized()
	# hop up small ledges when the path climbs
	jump_timer -= dt
	if next.y > player.global_position.y + 0.5 and jump_timer <= 0.0 and player.is_on_floor():
		cmd.buttons |= InputCmd.BTN_JUMP
		jump_timer = 1.0


func _aim_error_to(look_target: Vector3) -> float:
	var to := look_target - player.eye_position()
	return player.aim_direction().angle_to(to.normalized())


func _aim(look_target: Vector3, dt: float) -> void:
	if look_target == Vector3.INF:
		return
	var to := look_target - player.eye_position()
	if to.length() < 0.01:
		return
	noise_timer -= dt
	if noise_timer <= 0.0:
		noise_timer = 0.3
		aim_noise = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * deg_to_rad(profile.aim_error)
	var flat := Vector2(to.x, to.z)
	desired_yaw = atan2(-to.x, -to.z) + aim_noise.x
	desired_pitch = atan2(to.y, flat.length()) + aim_noise.y
	var t := clampf(profile.turn * dt, 0.0, 1.0)
	yaw = lerp_angle(yaw, desired_yaw, t)
	pitch = clampf(lerpf(pitch, desired_pitch, t), -1.4, 1.4)
	# compensate recoil partially at higher difficulties
	if difficulty >= 2:
		pitch -= deg_to_rad(player.recoil_offset.y) * (0.5 if difficulty == 2 else 0.85) * dt * 8.0


func _maybe_throw_grenade(cmd: InputCmd, toward: Vector3) -> void:
	if nade_cooldown > 0.0 or target != null or rng.randf() > profile.nade * 0.02:
		return
	var nades: Array = player.inventory.slots[Inventory.SLOT_GRENADE]
	if nades.is_empty():
		return
	var d := player.global_position.distance_to(toward)
	if d < 8.0 or d > 40.0:
		return
	# prefer smoke/flash before entering, frag when defending
	var pick := 0
	for i in range(nades.size()):
		if nades[i].cfg.id in ["smoke", "flash"]:
			pick = i
			break
	player.inventory.grenade_index = pick
	slot_request = Inventory.SLOT_GRENADE
	nade_cooldown = 6.0
	# fire on a later tick once the grenade is equipped
	get_tree().create_timer(0.9).timeout.connect(func():
		if player.alive and player.active_slot == Inventory.SLOT_GRENADE:
			player.throw_timer = 0.05
			player.throw_alt = false
			get_tree().create_timer(0.6).timeout.connect(_prefer_best_weapon))
