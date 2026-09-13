class_name WeaponConfig
extends Resource
## Data-driven balance for one weapon, grenade or objective item. Edit the .tres files in
## res://src/data/weapons (or regenerate them with tools/gen_weapon_data.py); never hard-code values.

enum FireMode { AUTO, SEMI, BURST, BOLT, PUMP, MELEE, THROW, NONE }

@export var id: String = ""
@export var display_name: String = ""
## pistol, smg, shotgun, rifle, sniper, lmg, melee, grenade, objective
@export var category: String = "rifle"
## primary, secondary, melee, grenade, bomb, kit
@export var slot: String = "primary"
## attackers / defenders / both — which team may buy it
@export var team: String = "both"
@export var price: int = 0
@export var kill_reward: int = 300
@export var model: String = ""

@export_group("Damage")
@export var damage: float = 30.0
@export_range(0.0, 1.0) var armor_penetration: float = 0.7
## Damage multiplier applied per 50 m of travel (0.98 = almost no falloff, 0.7 = shotgun).
@export_range(0.3, 1.0) var range_modifier: float = 0.9
@export var max_range: float = 400.0
@export var head_mult: float = 4.0
@export var chest_mult: float = 1.0
@export var stomach_mult: float = 1.25
@export var arm_mult: float = 1.0
@export var leg_mult: float = 0.75
@export var pellets: int = 1

@export_group("Firing")
@export var fire_mode: FireMode = FireMode.AUTO
@export var fire_rate_rpm: float = 600.0
@export var burst_count: int = 3
@export var burst_delay: float = 0.06
@export var mag_size: int = 30
@export var reserve_ammo: int = 90
@export var reload_time: float = 2.4
@export var reload_time_empty: float = 3.0
@export var equip_time: float = 0.9
@export var first_fire_delay: float = 0.15
@export var move_speed: float = 5.4
@export var zoom_levels: PackedFloat32Array = PackedFloat32Array()

@export_group("Accuracy (degrees of cone half-angle)")
@export var spread_base: float = 0.25
@export var inaccuracy_stand: float = 0.6
@export var inaccuracy_crouch: float = 0.35
@export var inaccuracy_move: float = 3.5
@export var inaccuracy_jump: float = 12.0
@export var inaccuracy_ladder: float = 4.0
## Inaccuracy added for every shot fired (decays with recoil_recovery_time).
@export var inaccuracy_fire: float = 0.5
@export var recoil_recovery_time: float = 0.45
## Speed (m/s) at which movement inaccuracy reaches its full value.
@export var move_inaccuracy_speed: float = 3.5

@export_group("Recoil")
@export var recoil_magnitude: float = 1.6
@export var recoil_seed: int = 1
## Explicit per-shot pattern (x = yaw deg, y = pitch deg). Empty = generated from recoil_seed.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()
@export var recoil_camera_ratio: float = 0.6
@export var view_kick: float = 1.0

@export_group("Melee")
@export var melee_range: float = 1.6
@export var melee_damage_light: float = 40.0
@export var melee_damage_heavy: float = 65.0
@export var backstab_mult: float = 3.0
@export var melee_heavy_delay: float = 0.95

@export_group("Grenade")
@export var throw_speed: float = 22.0
@export var fuse_time: float = 1.6
@export var effect_radius: float = 6.0
@export var effect_duration: float = 15.0
@export var effect_power: float = 98.0
@export var max_carry: int = 1

@export_group("Presentation")
@export var sound_class: String = "rifle"
@export var tracer: bool = true
@export var ejects_shells: bool = true
@export var fp_offset: Vector3 = Vector3(0.13, -0.17, -0.32)


func fire_interval() -> float:
	return 60.0 / max(fire_rate_rpm, 1.0)


func is_firearm() -> bool:
	return category in ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg"]


func is_grenade() -> bool:
	return category == "grenade"


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("missing id")
	if display_name.is_empty():
		errors.append("%s: missing display_name" % id)
	if category not in ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg", "melee", "grenade", "objective"]:
		errors.append("%s: bad category %s" % [id, category])
	if slot not in ["primary", "secondary", "melee", "grenade", "bomb", "kit"]:
		errors.append("%s: bad slot %s" % [id, slot])
	if team not in ["attackers", "defenders", "both"]:
		errors.append("%s: bad team %s" % [id, team])
	if price < 0 or price > 20000:
		errors.append("%s: price out of range" % id)
	if is_firearm():
		if damage <= 0.0 or damage > 500.0:
			errors.append("%s: damage out of range" % id)
		if mag_size <= 0 or reserve_ammo < 0:
			errors.append("%s: bad ammo" % id)
		if fire_rate_rpm <= 0.0 or fire_rate_rpm > 2000.0:
			errors.append("%s: bad fire rate" % id)
		if move_speed <= 0.0 or move_speed > 7.0:
			errors.append("%s: bad move speed" % id)
		if armor_penetration < 0.0 or armor_penetration > 1.0:
			errors.append("%s: bad armor penetration" % id)
		if range_modifier <= 0.0 or range_modifier > 1.0:
			errors.append("%s: bad range modifier" % id)
		if recoil_pattern.size() > 0 and recoil_pattern.size() < mag_size:
			errors.append("%s: recoil pattern shorter than magazine" % id)
		if reload_time <= 0.0 or equip_time <= 0.0:
			errors.append("%s: bad timings" % id)
		if pellets < 1:
			errors.append("%s: pellets < 1" % id)
	if is_grenade():
		if fuse_time <= 0.0 or effect_radius <= 0.0:
			errors.append("%s: bad grenade values" % id)
	if model.is_empty():
		errors.append("%s: missing model path" % id)
	return errors
