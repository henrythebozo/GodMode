class_name Inventory
extends RefCounted
## Weapon slots for one player. Server-owned; mirrored to the owning client through sync dictionaries.

const SLOT_PRIMARY := 0
const SLOT_SECONDARY := 1
const SLOT_MELEE := 2
const SLOT_GRENADE := 3
const SLOT_BOMB := 4
const SLOT_COUNT := 5

var slots: Array = [null, null, null, [], null]   # grenade slot holds an Array of WeaponState
var grenade_index: int = 0
var has_kit: bool = false
var purchases_this_round: Array = []              # weapon ids bought this round (for refunds)


func reset_to_default(team: int) -> void:
	slots = [null, null, null, [], null]
	grenade_index = 0
	has_kit = false
	purchases_this_round.clear()
	give(WeaponDB.get_config("knife"))
	give(WeaponDB.get_config("p9"))


func give(cfg: WeaponConfig) -> bool:
	if cfg == null:
		return false
	match cfg.slot:
		"primary":
			if slots[SLOT_PRIMARY] != null:
				return false
			slots[SLOT_PRIMARY] = WeaponState.new(cfg)
		"secondary":
			if slots[SLOT_SECONDARY] != null:
				return false
			slots[SLOT_SECONDARY] = WeaponState.new(cfg)
		"melee":
			if slots[SLOT_MELEE] != null:
				return false
			slots[SLOT_MELEE] = WeaponState.new(cfg)
		"grenade":
			var existing := find_grenade(cfg.id)
			if existing != null:
				if existing.ammo >= cfg.max_carry:
					return false
				existing.ammo += 1
				return true
			if grenade_total() >= 4:
				return false
			var ws := WeaponState.new(cfg)
			ws.ammo = 1
			ws.reserve = 0
			slots[SLOT_GRENADE].append(ws)
		"bomb":
			if slots[SLOT_BOMB] != null:
				return false
			slots[SLOT_BOMB] = WeaponState.new(cfg)
		"kit":
			if has_kit:
				return false
			has_kit = true
		_:
			return false
	return true


func find_grenade(id: String) -> WeaponState:
	for g in slots[SLOT_GRENADE]:
		if g.cfg.id == id:
			return g
	return null


func grenade_total() -> int:
	var n := 0
	for g in slots[SLOT_GRENADE]:
		n += g.ammo
	return n


func get_active(slot: int) -> WeaponState:
	if slot == SLOT_GRENADE:
		var gs: Array = slots[SLOT_GRENADE]
		if gs.is_empty():
			return null
		grenade_index = clampi(grenade_index, 0, gs.size() - 1)
		return gs[grenade_index]
	if slot < 0 or slot >= SLOT_COUNT:
		return null
	return slots[slot]


func has_slot(slot: int) -> bool:
	return get_active(slot) != null


func remove(slot: int, grenade_id: String = "") -> WeaponState:
	if slot == SLOT_GRENADE:
		for i in range(slots[SLOT_GRENADE].size()):
			var g: WeaponState = slots[SLOT_GRENADE][i]
			if grenade_id.is_empty() or g.cfg.id == grenade_id:
				g.ammo -= 1
				if g.ammo <= 0:
					slots[SLOT_GRENADE].remove_at(i)
					grenade_index = 0
				return g
		return null
	var ws: WeaponState = slots[slot]
	slots[slot] = null
	return ws


func remove_by_id(id: String) -> WeaponState:
	for slot in [SLOT_PRIMARY, SLOT_SECONDARY, SLOT_MELEE, SLOT_BOMB]:
		if slots[slot] != null and slots[slot].cfg.id == id:
			return remove(slot)
	if find_grenade(id) != null:
		return remove(SLOT_GRENADE, id)
	return null


func has_weapon(id: String) -> bool:
	for slot in [SLOT_PRIMARY, SLOT_SECONDARY, SLOT_MELEE, SLOT_BOMB]:
		if slots[slot] != null and slots[slot].cfg.id == id:
			return true
	return find_grenade(id) != null


func has_bomb() -> bool:
	return slots[SLOT_BOMB] != null


func next_slot_with_weapon(from: int, dir: int) -> int:
	var s := from
	for i in range(SLOT_COUNT):
		s = posmod(s + dir, SLOT_COUNT)
		if has_slot(s):
			return s
	return from


func best_slot() -> int:
	for s in [SLOT_PRIMARY, SLOT_SECONDARY, SLOT_MELEE]:
		if has_slot(s):
			return s
	return SLOT_MELEE


func value() -> int:
	var v := 0
	for slot in [SLOT_PRIMARY, SLOT_SECONDARY]:
		if slots[slot] != null:
			v += slots[slot].cfg.price
	for g in slots[SLOT_GRENADE]:
		v += g.cfg.price * g.ammo
	return v


func serialize() -> Dictionary:
	var d := {"kit": has_kit, "gi": grenade_index, "slots": [], "nades": []}
	for slot in [SLOT_PRIMARY, SLOT_SECONDARY, SLOT_MELEE, SLOT_BOMB]:
		d.slots.append(slots[slot].to_dict() if slots[slot] != null else null)
	for g in slots[SLOT_GRENADE]:
		d.nades.append(g.to_dict())
	return d


func deserialize(d: Dictionary) -> void:
	has_kit = d.get("kit", false)
	grenade_index = d.get("gi", 0)
	var idx := 0
	for slot in [SLOT_PRIMARY, SLOT_SECONDARY, SLOT_MELEE, SLOT_BOMB]:
		var sd = d.slots[idx]
		idx += 1
		if sd == null:
			slots[slot] = null
			continue
		if slots[slot] == null or slots[slot].cfg.id != sd.id:
			slots[slot] = WeaponState.new(WeaponDB.get_config(sd.id))
		slots[slot].apply_dict(sd)
	var new_nades := []
	for nd in d.nades:
		var existing := find_grenade(nd.id)
		var ws: WeaponState = existing if existing != null else WeaponState.new(WeaponDB.get_config(nd.id))
		ws.apply_dict(nd)
		new_nades.append(ws)
	slots[SLOT_GRENADE] = new_nades
