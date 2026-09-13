extends Node
## Autoload: loads every WeaponConfig from res://src/data/weapons and validates it once at startup.

const WEAPON_DIR := "res://src/data/weapons"

var weapons: Dictionary = {}          # id -> WeaponConfig
var by_category: Dictionary = {}      # category -> Array[WeaponConfig]
var load_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	load_all()


func load_all() -> void:
	weapons.clear()
	by_category.clear()
	load_errors.clear()
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		push_error("WeaponDB: cannot open %s" % WEAPON_DIR)
		return
	for f in dir.get_files():
		if not (f.ends_with(".tres") or f.ends_with(".tres.remap")):
			continue
		var path := WEAPON_DIR + "/" + f.trim_suffix(".remap")
		var res := load(path)
		if res is WeaponConfig:
			var errs: PackedStringArray = res.validate()
			if errs.size() > 0:
				for e in errs:
					load_errors.append(e)
					push_error("WeaponDB: " + e)
			weapons[res.id] = res
			if not by_category.has(res.category):
				by_category[res.category] = []
			by_category[res.category].append(res)
	for cat in by_category:
		by_category[cat].sort_custom(func(a, b): return a.price < b.price)
	var pattern_gen := RecoilPattern.new()
	for w in weapons.values():
		if w.is_firearm() and w.recoil_pattern.is_empty():
			w.recoil_pattern = pattern_gen.generate(w)


func get_config(id: String) -> WeaponConfig:
	return weapons.get(id)


func has(id: String) -> bool:
	return weapons.has(id)


func buyable(team: int) -> Array:
	var team_name := "attackers" if team == 1 else "defenders"
	var out := []
	for w in weapons.values():
		if w.price <= 0 and w.category != "objective":
			continue
		if w.id == "bomb":
			continue
		if w.team == "both" or w.team == team_name:
			out.append(w)
	out.sort_custom(func(a, b): return a.price < b.price if a.category == b.category else a.category < b.category)
	return out
