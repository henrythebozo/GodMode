class_name NetProtocol
extends RefCounted
## Binary packing for snapshots. Weapon ids are sent as indices into a sorted id table that both
## sides derive from WeaponDB, keeping snapshots small.

static var _weapon_ids: PackedStringArray = PackedStringArray()

const F_ALIVE := 1
const F_LADDER := 2
const F_FLOOR := 4
const F_RELOADING := 8
const F_ZOOMED := 16
const F_HELMET := 32
const F_KIT := 64
const F_BOMB := 128


static func weapon_ids() -> PackedStringArray:
	if _weapon_ids.is_empty():
		var ids := WeaponDB.weapons.keys()
		ids.sort()
		_weapon_ids = PackedStringArray(ids)
	return _weapon_ids


static func weapon_index(id: String) -> int:
	var idx := weapon_ids().find(id)
	return idx + 1 if idx >= 0 else 0


static func weapon_from_index(i: int) -> String:
	if i <= 0 or i > weapon_ids().size():
		return ""
	return weapon_ids()[i - 1]


static func put_vec3(buf: StreamPeerBuffer, v: Vector3) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
	buf.put_float(v.z)


static func get_vec3(buf: StreamPeerBuffer) -> Vector3:
	var x := buf.get_float()
	var y := buf.get_float()
	var z := buf.get_float()
	return Vector3(x, y, z)


static func pack_snapshot(tick: int, states: Array, entities: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	buf.put_u8(states.size())
	for s in states:
		buf.put_32(s.id)
		buf.put_u32(s.tick)
		put_vec3(buf, s.p)
		put_vec3(buf, s.v)
		buf.put_float(s.yaw)
		buf.put_float(s.pitch)
		var flags := 0
		if s.alive: flags |= F_ALIVE
		if s.ladder: flags |= F_LADDER
		if s.floor: flags |= F_FLOOR
		if s.reloading: flags |= F_RELOADING
		if s.zoomed: flags |= F_ZOOMED
		if s.helmet: flags |= F_HELMET
		if s.kit: flags |= F_KIT
		if s.bomb: flags |= F_BOMB
		buf.put_u8(flags)
		buf.put_u8(int(clampf(s.crouch, 0.0, 1.0) * 255.0))
		buf.put_u8(clampi(s.hp, 0, 255))
		buf.put_u8(clampi(s.armor, 0, 255))
		buf.put_u8(weapon_index(s.weapon))
		buf.put_u8(s.slot)
		buf.put_u8(int(clampf(max(s.plant, s.defuse), 0.0, 1.0) * 255.0))
		buf.put_u16(clampi(s.ammo, 0, 65535))
		buf.put_u16(clampi(s.reserve, 0, 65535))
		buf.put_float(s.recoil.x)
		buf.put_float(s.recoil.y)
	buf.put_u8(entities.size())
	for e in entities:
		buf.put_u16(e.id)
		buf.put_u8(e.type)
		put_vec3(buf, e.p)
		put_vec3(buf, e.v)
		buf.put_u8(weapon_index(e.get("weapon", "")))
	return buf.data_array


static func unpack_snapshot(bytes: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var out := {"tick": buf.get_u32(), "players": [], "entities": []}
	var n := buf.get_u8()
	for i in n:
		var s := {}
		s.id = buf.get_32()
		s.tick = buf.get_u32()
		s.p = get_vec3(buf)
		s.v = get_vec3(buf)
		s.yaw = buf.get_float()
		s.pitch = buf.get_float()
		var flags := buf.get_u8()
		s.alive = (flags & F_ALIVE) != 0
		s.ladder = (flags & F_LADDER) != 0
		s.floor = (flags & F_FLOOR) != 0
		s.reloading = (flags & F_RELOADING) != 0
		s.zoomed = (flags & F_ZOOMED) != 0
		s.helmet = (flags & F_HELMET) != 0
		s.kit = (flags & F_KIT) != 0
		s.bomb = (flags & F_BOMB) != 0
		s.crouch = buf.get_u8() / 255.0
		s.hp = buf.get_u8()
		s.armor = buf.get_u8()
		s.weapon = weapon_from_index(buf.get_u8())
		s.slot = buf.get_u8()
		s.progress = buf.get_u8() / 255.0
		s.ammo = buf.get_u16()
		s.reserve = buf.get_u16()
		var rx := buf.get_float()
		var ry := buf.get_float()
		s.recoil = Vector2(rx, ry)
		out.players.append(s)
	var m := buf.get_u8()
	for i in m:
		var e := {}
		e.id = buf.get_u16()
		e.type = buf.get_u8()
		e.p = get_vec3(buf)
		e.v = get_vec3(buf)
		e.weapon = weapon_from_index(buf.get_u8())
		out.entities.append(e)
	return out
