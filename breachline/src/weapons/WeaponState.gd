class_name WeaponState
extends RefCounted
## Per-instance weapon simulation (ammo, timers, recoil index). Shared by the server, client
## prediction and bots: everything is driven by `tick(dt, cmd)` with no scene access.

var cfg: WeaponConfig
var ammo: int = 0
var reserve: int = 0
var next_fire_time: float = 0.0     # seconds until the weapon can fire again
var reload_timer: float = -1.0      # >= 0 while reloading
var equip_timer: float = 0.0        # >= 0 while drawing
var shots_in_burst: int = 0
var burst_left: int = 0
var burst_timer: float = 0.0
var consecutive_shots: int = 0      # index into the recoil pattern
var recoil_decay_timer: float = 0.0
var inaccuracy_extra: float = 0.0   # added by firing, decays over recoil_recovery_time
var zoom_level: int = 0
var pending_pump: float = -1.0
var bought_this_round: bool = false
var trigger_held: bool = false
var inspect_timer: float = -1.0


func _init(config: WeaponConfig = null) -> void:
	if config:
		setup(config)


func setup(config: WeaponConfig) -> void:
	cfg = config
	ammo = config.mag_size
	reserve = config.reserve_ammo
	equip_timer = config.equip_time


func on_equip() -> void:
	equip_timer = cfg.equip_time
	reload_timer = -1.0
	burst_left = 0
	consecutive_shots = 0
	inspect_timer = -1.0
	next_fire_time = max(next_fire_time, cfg.first_fire_delay)


func on_holster() -> void:
	reload_timer = -1.0
	burst_left = 0
	inspect_timer = -1.0


func is_busy() -> bool:
	return equip_timer > 0.0 or reload_timer >= 0.0


func can_fire() -> bool:
	return not is_busy() and next_fire_time <= 0.0 and pending_pump < 0.0 and (ammo > 0 or cfg.category == "melee" or cfg.category == "grenade")


func can_reload() -> bool:
	return cfg.is_firearm() and not is_busy() and ammo < cfg.mag_size and reserve > 0


func start_reload() -> bool:
	if not can_reload():
		return false
	reload_timer = cfg.reload_time_empty if ammo == 0 else cfg.reload_time
	burst_left = 0
	inspect_timer = -1.0
	return true


func start_inspect() -> bool:
	if is_busy() or inspect_timer >= 0.0:
		return false
	inspect_timer = 2.6
	return true


## Advance timers. Returns a list of events: "reloaded", "pumped", "burst_shot", "equipped"
func tick(dt: float) -> PackedStringArray:
	var events := PackedStringArray()
	if equip_timer > 0.0:
		equip_timer -= dt
		if equip_timer <= 0.0:
			events.append("equipped")
	if next_fire_time > 0.0:
		next_fire_time -= dt
	if inspect_timer >= 0.0:
		inspect_timer -= dt
	if reload_timer >= 0.0:
		reload_timer -= dt
		if reload_timer < 0.0:
			_finish_reload()
			events.append("reloaded")
			# pump/tube shotguns load one shell at a time
			if cfg.fire_mode == WeaponConfig.FireMode.PUMP and ammo < cfg.mag_size and reserve > 0:
				reload_timer = cfg.reload_time
	if pending_pump >= 0.0:
		pending_pump -= dt
		if pending_pump < 0.0:
			events.append("pumped")
	if burst_left > 0:
		burst_timer -= dt
		if burst_timer <= 0.0 and ammo > 0:
			burst_timer = cfg.burst_delay / max(cfg.burst_count - 1, 1)
			burst_left -= 1
			ammo -= 1
			consecutive_shots += 1
			_apply_fire_inaccuracy()
			events.append("burst_shot")
		elif ammo <= 0:
			burst_left = 0
	if recoil_decay_timer > 0.0:
		recoil_decay_timer -= dt
		if recoil_decay_timer <= 0.0:
			consecutive_shots = 0
	if inaccuracy_extra > 0.0:
		inaccuracy_extra = max(0.0, inaccuracy_extra - dt * (cfg.inaccuracy_fire * 3.0 / max(cfg.recoil_recovery_time, 0.05)))
	return events


func _finish_reload() -> void:
	if cfg.fire_mode == WeaponConfig.FireMode.PUMP:
		var n: int = min(1, reserve)
		ammo += n
		reserve -= n
	else:
		var need: int = cfg.mag_size - ammo
		var n: int = min(need, reserve)
		ammo += n
		reserve -= n


func _apply_fire_inaccuracy() -> void:
	inaccuracy_extra = min(inaccuracy_extra + cfg.inaccuracy_fire, cfg.inaccuracy_fire * 6.0)
	recoil_decay_timer = cfg.recoil_recovery_time


## Attempt to fire given the trigger state. Returns true when a shot is produced this call.
func try_fire(trigger_pressed: bool, trigger_just_pressed: bool) -> bool:
	if not cfg.is_firearm():
		return false
	if not can_fire():
		return false
	if reload_timer >= 0.0 and ammo > 0 and cfg.fire_mode == WeaponConfig.FireMode.PUMP:
		reload_timer = -1.0   # interrupt shell loading to fire
	match cfg.fire_mode:
		WeaponConfig.FireMode.AUTO:
			if not trigger_pressed:
				return false
		WeaponConfig.FireMode.SEMI, WeaponConfig.FireMode.BOLT, WeaponConfig.FireMode.PUMP:
			if not trigger_just_pressed:
				return false
		WeaponConfig.FireMode.BURST:
			if not trigger_just_pressed or burst_left > 0:
				return false
	ammo -= 1
	consecutive_shots += 1
	next_fire_time = cfg.fire_interval()
	_apply_fire_inaccuracy()
	match cfg.fire_mode:
		WeaponConfig.FireMode.BURST:
			burst_left = cfg.burst_count - 1
			burst_timer = cfg.burst_delay / max(cfg.burst_count - 1, 1)
			next_fire_time = cfg.fire_interval() + cfg.burst_delay
		WeaponConfig.FireMode.PUMP, WeaponConfig.FireMode.BOLT:
			pending_pump = cfg.fire_interval() * 0.6
	return true


## Current cone half-angle in degrees for a player state.
func inaccuracy(speed: float, crouching: bool, in_air: bool, on_ladder: bool, zoomed: bool) -> float:
	var base := cfg.inaccuracy_crouch if crouching else cfg.inaccuracy_stand
	if in_air:
		base = cfg.inaccuracy_jump
	elif on_ladder:
		base = cfg.inaccuracy_ladder
	var move := clampf(speed / max(cfg.move_inaccuracy_speed, 0.1), 0.0, 1.0)
	base += cfg.inaccuracy_move * move * move
	if zoomed and cfg.category == "sniper":
		base *= 0.04
	elif zoomed:
		base *= 0.7
	return cfg.spread_base + base + inaccuracy_extra


func recoil_for_shot(index: int) -> Vector2:
	if cfg.recoil_pattern.is_empty():
		return Vector2(0, cfg.recoil_magnitude)
	return cfg.recoil_pattern[clampi(index, 0, cfg.recoil_pattern.size() - 1)]


func to_dict() -> Dictionary:
	return {"id": cfg.id, "ammo": ammo, "reserve": reserve, "zoom": zoom_level, "bought": bought_this_round}


func apply_dict(d: Dictionary) -> void:
	ammo = int(d.get("ammo", ammo))
	reserve = int(d.get("reserve", reserve))
	zoom_level = int(d.get("zoom", zoom_level))
	bought_this_round = bool(d.get("bought", bought_this_round))
