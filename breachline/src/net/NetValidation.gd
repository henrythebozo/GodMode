class_name NetValidation
extends RefCounted
## Sanity checks on client-originated data. Not an anti-cheat: it rejects impossible values so a
## broken or malicious client cannot crash the server or claim things the simulation never produced.

const MAX_MOVE_MAGNITUDE := 1.02
const MAX_TICK_LEAD := 8              # client ticks may run slightly ahead of the server
const MAX_CMDS_PER_TICK := 4          # catch-up limit after a hitch; more is dropped
const MAX_NAME_LENGTH := 24
const MAX_CHAT_LENGTH := 200


static func sanitize_cmd(cmd: InputCmd, server_tick: int) -> bool:
	if not is_finite(cmd.yaw) or not is_finite(cmd.pitch) or not is_finite(cmd.move.x) or not is_finite(cmd.move.y):
		return false
	if cmd.move.length() > MAX_MOVE_MAGNITUDE:
		cmd.move = cmd.move.normalized()
	cmd.pitch = clampf(cmd.pitch, -PI / 2.0, PI / 2.0)
	cmd.yaw = wrapf(cmd.yaw, -PI, PI)
	if cmd.view_tick > server_tick:
		cmd.view_tick = server_tick
	if cmd.weapon_slot < -1 or cmd.weapon_slot >= Inventory.SLOT_COUNT:
		cmd.weapon_slot = -1
	return true


static func sanitize_name(n: String) -> String:
	var s := n.strip_edges().substr(0, MAX_NAME_LENGTH)
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch != "[" and ch != "]":
			out += ch
	return out if not out.is_empty() else "Operator"


static func sanitize_chat(t: String) -> String:
	return t.strip_edges().substr(0, MAX_CHAT_LENGTH).replace("[", "(").replace("]", ")")


static func valid_weapon_id(id: String) -> bool:
	return WeaponDB.has(id)
