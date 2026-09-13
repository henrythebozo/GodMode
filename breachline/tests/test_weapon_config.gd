extends TestCase


func test_all_weapons_load_and_validate() -> void:
	assert_true(WeaponDB.weapons.size() >= 24, "at least 24 weapon resources loaded (got %d)" % WeaponDB.weapons.size())
	assert_eq(WeaponDB.load_errors.size(), 0, "no validation errors: " + ", ".join(WeaponDB.load_errors))
	for id in WeaponDB.weapons:
		var w: WeaponConfig = WeaponDB.weapons[id]
		assert_eq(w.id, id, "id matches file")
		assert_true(ResourceLoader.exists(w.model), "model exists for " + id)


func test_every_category_present() -> void:
	for cat in ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg", "melee", "grenade", "objective"]:
		assert_true(WeaponDB.by_category.has(cat), "category " + cat)
	for id in ["frag", "flash", "smoke", "incendiary", "decoy", "bomb", "defuse_kit", "knife"]:
		assert_true(WeaponDB.has(id), "has " + id)


func test_validation_catches_bad_values() -> void:
	var w := WeaponConfig.new()
	w.id = "bad"
	w.display_name = "Bad"
	w.category = "rifle"
	w.model = "res://x.glb"
	w.damage = -5
	w.mag_size = 0
	w.move_speed = 50
	var errs := w.validate()
	assert_true(errs.size() >= 3, "several errors reported: " + ", ".join(errs))
	w.category = "laser"
	assert_true("bad category" in ", ".join(w.validate()), "category checked")


func test_recoil_patterns_generated_and_deterministic() -> void:
	var gen := RecoilPattern.new()
	var a := gen.generate(WeaponDB.get_config("corsair"))
	var b := gen.generate(WeaponDB.get_config("corsair"))
	assert_eq(a.size(), 30, "one entry per bullet")
	assert_true(a == b, "same seed gives the same pattern")
	var c := gen.generate(WeaponDB.get_config("lynx"))
	assert_true(a != c, "different weapons differ")
	assert_true(a[0].y > 0.0, "first shot kicks upward")


func test_weapon_state_fire_and_reload() -> void:
	var w := WeaponState.new(WeaponDB.get_config("corsair"))
	w.equip_timer = 0.0
	w.next_fire_time = 0.0
	assert_true(w.try_fire(true, true), "auto fires when held")
	assert_eq(w.ammo, 29)
	assert_true(not w.try_fire(true, false), "respects fire interval")
	w.tick(w.cfg.fire_interval() + 0.001)
	assert_true(w.try_fire(true, false), "auto keeps firing while held")
	var semi := WeaponState.new(WeaponDB.get_config("p9"))
	semi.equip_timer = 0.0
	semi.next_fire_time = 0.0
	assert_true(semi.try_fire(true, true))
	semi.tick(1.0)
	assert_true(not semi.try_fire(true, false), "semi needs a new press")
	assert_true(semi.try_fire(true, true))
	semi.ammo = 0
	assert_true(not semi.try_fire(true, true), "empty cannot fire")
	assert_true(semi.start_reload(), "reload starts")
	assert_true(semi.is_busy())
	semi.tick(semi.cfg.reload_time_empty + 0.01)
	assert_eq(semi.ammo, semi.cfg.mag_size, "magazine refilled")
	assert_eq(semi.reserve, semi.cfg.reserve_ammo - semi.cfg.mag_size, "reserve reduced")


func test_burst_and_pump_modes() -> void:
	var burst := WeaponState.new(WeaponDB.get_config("falcon"))
	burst.equip_timer = 0.0
	burst.next_fire_time = 0.0
	assert_true(burst.try_fire(true, true))
	var shots := 1
	for i in 20:
		for ev in burst.tick(0.05):
			if ev == "burst_shot":
				shots += 1
	assert_eq(shots, 3, "three-round burst")
	var pump := WeaponState.new(WeaponDB.get_config("breaker"))
	pump.equip_timer = 0.0
	pump.next_fire_time = 0.0
	assert_true(pump.try_fire(true, true))
	assert_true(not pump.can_fire(), "pump action pending")
	pump.tick(2.0)
	assert_true(pump.can_fire(), "pumped")


func test_inaccuracy_modifiers() -> void:
	var w := WeaponState.new(WeaponDB.get_config("corsair"))
	var stand := w.inaccuracy(0.0, false, false, false, false)
	var crouch := w.inaccuracy(0.0, true, false, false, false)
	var move := w.inaccuracy(5.0, false, false, false, false)
	var jump := w.inaccuracy(0.0, false, true, false, false)
	assert_true(crouch < stand, "crouch more accurate")
	assert_true(move > stand, "moving less accurate")
	assert_true(jump > move, "jumping worst")
	var sniper := WeaponState.new(WeaponDB.get_config("longbow"))
	assert_true(sniper.inaccuracy(0, false, false, false, true) < sniper.inaccuracy(0, false, false, false, false) * 0.1, "scoped sniper accurate")


func test_inventory_rules() -> void:
	var inv := Inventory.new()
	inv.reset_to_default(Teams.ATTACKERS)
	assert_true(inv.has_slot(Inventory.SLOT_MELEE) and inv.has_slot(Inventory.SLOT_SECONDARY), "default loadout")
	assert_true(inv.give(WeaponDB.get_config("corsair")), "primary accepted")
	assert_true(not inv.give(WeaponDB.get_config("lynx")), "second primary rejected")
	assert_true(inv.give(WeaponDB.get_config("flash")), "flash 1")
	assert_true(inv.give(WeaponDB.get_config("flash")), "flash 2")
	assert_true(not inv.give(WeaponDB.get_config("flash")), "flash max carry 2")
	assert_eq(inv.grenade_total(), 2)
	var d := inv.serialize()
	var inv2 := Inventory.new()
	inv2.deserialize(d)
	assert_true(inv2.has_weapon("corsair") and inv2.find_grenade("flash").ammo == 2, "round trip serialize")


func test_match_rules_validate() -> void:
	var rules: MatchRules = load("res://src/data/rules_competitive.tres")
	assert_eq(rules.validate().size(), 0, "rules valid")
	assert_eq(rules.halftime_round(), 12)
