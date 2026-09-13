class_name LagCompensation
extends RefCounted
## Ring buffer of player poses per server tick so shots can be resolved against where the
## victim was when the shooter saw them. Purely analytic (see Hitboxes), no physics rewinding.

const HISTORY_TICKS := 64          # 1 s at 64 Hz
const MAX_REWIND_TICKS := 20       # ~310 ms; clients further behind are resolved at the oldest pose

var _history: Dictionary = {}      # peer_id -> Array of {tick, pos, yaw, crouch, alive}


func record(player: Player, tick: int) -> void:
	var arr: Array = _history.get(player.peer_id, [])
	arr.append({"tick": tick, "pos": player.global_position if player.is_inside_tree() else player.position, "yaw": player.yaw, "crouch": player.crouching, "alive": player.alive})
	while arr.size() > HISTORY_TICKS:
		arr.pop_front()
	_history[player.peer_id] = arr


func forget(peer_id: int) -> void:
	_history.erase(peer_id)


## Pose of `peer_id` at `tick` (clamped to the allowed rewind window); null if unknown.
func pose_at(peer_id: int, tick: int, current_tick: int) -> Dictionary:
	var arr: Array = _history.get(peer_id, [])
	if arr.is_empty():
		return {}
	var target: int = clampi(tick, current_tick - MAX_REWIND_TICKS, current_tick)
	var prev: Dictionary = arr[0]
	for rec in arr:
		if rec.tick == target:
			return rec
		if rec.tick > target:
			# interpolate between prev and rec
			var span: int = rec.tick - prev.tick
			var t: float = 0.0 if span <= 0 else float(target - prev.tick) / float(span)
			return {"tick": target, "pos": prev.pos.lerp(rec.pos, t), "yaw": lerp_angle(prev.yaw, rec.yaw, t), "crouch": rec.crouch, "alive": rec.alive}
		prev = rec
	return arr[-1]


func transform_for(rec: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rec.yaw), rec.pos)
