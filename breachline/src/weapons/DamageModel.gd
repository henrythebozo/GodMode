class_name DamageModel
extends RefCounted
## Pure damage math. Server-only in practice, but side-effect free so it is unit tested.

enum Zone { NONE, HEAD, CHEST, STOMACH, ARM, LEG }

## Result dictionary: {damage:int, armor_damage:int, armor_hit:bool, headshot:bool}
static func compute(cfg: WeaponConfig, zone: int, distance: float, armor: int, has_helmet: bool) -> Dictionary:
	var mult := 1.0
	match zone:
		Zone.HEAD: mult = cfg.head_mult
		Zone.CHEST: mult = cfg.chest_mult
		Zone.STOMACH: mult = cfg.stomach_mult
		Zone.ARM: mult = cfg.arm_mult
		Zone.LEG: mult = cfg.leg_mult
	var falloff := pow(cfg.range_modifier, max(distance, 0.0) / 50.0)
	if distance > cfg.max_range:
		falloff *= 0.5
	var raw := cfg.damage * mult * falloff
	var armor_hit := false
	var armor_damage := 0
	var final := raw
	if armor > 0:
		var covered := false
		match zone:
			Zone.HEAD: covered = has_helmet
			Zone.CHEST, Zone.STOMACH, Zone.ARM: covered = true
			_: covered = false
		if covered:
			armor_hit = true
			var after := raw * cfg.armor_penetration
			var blocked := raw - after
			armor_damage = int(ceil(blocked * 0.5))
			if armor_damage > armor:
				# armor broke mid-hit: the unblocked remainder goes through at full value
				var fraction := float(armor) / float(armor_damage)
				after = after * fraction + raw * (1.0 - fraction)
				armor_damage = armor
			final = after
	var dmg: int = int(round(final))
	return {"damage": max(dmg, 1 if raw > 0.0 else 0), "armor_damage": armor_damage, "armor_hit": armor_hit, "headshot": zone == Zone.HEAD}


## Explosive damage with linear falloff from the centre; occlusion is handled by the caller.
static func explosion(cfg: WeaponConfig, distance: float, armor: int) -> Dictionary:
	if distance >= cfg.effect_radius:
		return {"damage": 0, "armor_damage": 0, "armor_hit": false, "headshot": false}
	var falloff := 1.0 - (distance / cfg.effect_radius)
	var raw := cfg.effect_power * falloff * falloff
	var final := raw
	var armor_damage := 0
	var armor_hit := false
	if armor > 0:
		armor_hit = true
		final = raw * cfg.armor_penetration
		armor_damage = mini(int(ceil((raw - final) * 0.5)), armor)
	return {"damage": int(round(final)), "armor_damage": armor_damage, "armor_hit": armor_hit, "headshot": false}


static func fall_damage(rules: MatchRules, impact_speed: float) -> int:
	if impact_speed < rules.fall_damage_min_speed:
		return 0
	return int(round((impact_speed - rules.fall_damage_min_speed) * rules.fall_damage_per_speed))


static func zone_name(zone: int) -> String:
	match zone:
		Zone.HEAD: return "head"
		Zone.CHEST: return "chest"
		Zone.STOMACH: return "stomach"
		Zone.ARM: return "arm"
		Zone.LEG: return "leg"
	return "none"
