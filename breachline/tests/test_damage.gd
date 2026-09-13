extends TestCase


func test_headshot_multiplier_and_falloff() -> void:
	var rifle := WeaponDB.get_config("corsair")
	var body := DamageModel.compute(rifle, DamageModel.Zone.CHEST, 0.0, 0, false)
	var head := DamageModel.compute(rifle, DamageModel.Zone.HEAD, 0.0, 0, false)
	assert_eq(body.damage, 36, "point blank chest = base damage")
	assert_eq(head.damage, 144, "headshot x4")
	assert_true(head.headshot, "headshot flag")
	var far := DamageModel.compute(rifle, DamageModel.Zone.CHEST, 100.0, 0, false)
	assert_true(far.damage < body.damage, "damage falls off with distance")
	assert_eq(far.damage, int(round(36.0 * pow(0.9, 2.0))), "falloff formula")


func test_zone_multipliers() -> void:
	var w := WeaponDB.get_config("lynx")
	assert_eq(DamageModel.compute(w, DamageModel.Zone.STOMACH, 0, 0, false).damage, int(round(33.0 * 1.25)))
	assert_eq(DamageModel.compute(w, DamageModel.Zone.LEG, 0, 0, false).damage, int(round(33.0 * 0.75)))
	assert_eq(DamageModel.compute(w, DamageModel.Zone.ARM, 0, 0, false).damage, 33)


func test_armor_reduces_and_absorbs() -> void:
	var w := WeaponDB.get_config("corsair")   # pen 0.78
	var r := DamageModel.compute(w, DamageModel.Zone.CHEST, 0, 100, false)
	assert_true(r.armor_hit, "chest is armoured")
	assert_eq(r.damage, int(round(36.0 * 0.78)), "penetration applied")
	assert_eq(r.armor_damage, int(ceil((36.0 - 36.0 * 0.78) * 0.5)), "armor loses half of blocked")
	var legs := DamageModel.compute(w, DamageModel.Zone.LEG, 0, 100, false)
	assert_true(not legs.armor_hit, "legs not armoured")


func test_helmet_only_protects_head_when_worn() -> void:
	var w := WeaponDB.get_config("p9")
	var no_helmet := DamageModel.compute(w, DamageModel.Zone.HEAD, 0, 100, false)
	var helmet := DamageModel.compute(w, DamageModel.Zone.HEAD, 0, 100, true)
	assert_true(not no_helmet.armor_hit, "no helmet: head unprotected")
	assert_true(helmet.armor_hit, "helmet protects head")
	assert_true(helmet.damage < no_helmet.damage, "helmet reduces headshot damage")


func test_armor_breaking_mid_hit() -> void:
	var w := WeaponDB.get_config("longbow")   # 115 dmg pen 0.98
	var r := DamageModel.compute(w, DamageModel.Zone.CHEST, 0, 1, false)
	assert_true(r.armor_damage <= 1, "cannot lose more armor than owned")
	assert_true(r.damage >= 112, "almost full damage through 1 armor")


func test_explosion_falloff() -> void:
	var frag := WeaponDB.get_config("frag")
	var centre := DamageModel.explosion(frag, 0.0, 0)
	var edge := DamageModel.explosion(frag, frag.effect_radius, 0)
	var mid := DamageModel.explosion(frag, frag.effect_radius * 0.5, 0)
	assert_eq(centre.damage, 98, "full power at centre")
	assert_eq(edge.damage, 0, "nothing at the edge")
	assert_true(mid.damage > 0 and mid.damage < centre.damage, "quadratic falloff")


func test_fall_damage() -> void:
	var rules: MatchRules = load("res://src/data/rules_competitive.tres")
	assert_eq(DamageModel.fall_damage(rules, 5.0), 0, "small drops are free")
	assert_eq(DamageModel.fall_damage(rules, 9.0), 0, "threshold")
	assert_eq(DamageModel.fall_damage(rules, 12.0), 18, "3 m/s over threshold * 6")


func test_hitboxes_head_vs_chest() -> void:
	var xf := Transform3D(Basis(), Vector3(0, 0, 0))
	var head := Hitboxes.raycast(xf, false, Vector3(0, 1.66, -5), Vector3(0, 0, 1), 20.0)
	assert_true(head.hit and head.zone == DamageModel.Zone.HEAD, "ray at head height hits head")
	var chest := Hitboxes.raycast(xf, false, Vector3(0, 1.3, -5), Vector3(0, 0, 1), 20.0)
	assert_true(chest.hit and chest.zone == DamageModel.Zone.CHEST, "ray at chest height hits chest")
	var miss := Hitboxes.raycast(xf, false, Vector3(2, 1.3, -5), Vector3(0, 0, 1), 20.0)
	assert_true(not miss.hit, "ray 2 m to the side misses")
	var crouched := Hitboxes.raycast(xf, true, Vector3(0, 1.66, -5), Vector3(0, 0, 1), 20.0)
	assert_true(not crouched.hit or crouched.zone != DamageModel.Zone.HEAD, "crouching lowers the head")
	var rotated := Transform3D(Basis(Vector3.UP, PI), Vector3(3, 0, 3))
	var r := Hitboxes.raycast(rotated, false, Vector3(3, 1.0, -5), Vector3(0, 0, 1), 20.0)
	assert_true(r.hit and r.zone == DamageModel.Zone.STOMACH, "transform applied to hurtboxes")
	assert_near(r.distance, 8.0 - 0.20, 0.05, "distance to stomach capsule surface")
