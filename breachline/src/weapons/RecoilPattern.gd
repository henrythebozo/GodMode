class_name RecoilPattern
extends RefCounted
## Deterministic recoil pattern generation. Both server and client derive the same pattern
## from the weapon's seed, so the client can predict view kick without a round-trip.

## Returns one (yaw, pitch) kick in degrees per shot, mag_size entries long.
func generate(cfg: WeaponConfig) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.recoil_seed * 7919 + cfg.mag_size
	var out := PackedVector2Array()
	var mag := cfg.recoil_magnitude
	var n: int = max(cfg.mag_size, 1)
	var drift := 0.0            # slow horizontal wander that creates the classic "pattern"
	var drift_dir := 1.0 if rng.randf() > 0.5 else -1.0
	for i in range(n):
		var t := float(i) / float(max(n - 1, 1))
		# first shots climb almost straight up, later ones sweep sideways
		var vertical := mag * lerpf(1.0, 0.45, clampf(t * 1.8, 0.0, 1.0)) * rng.randf_range(0.85, 1.15)
		if i % 9 == 8:
			drift_dir *= -1.0
		drift += drift_dir * mag * rng.randf_range(0.12, 0.35) * clampf(t * 2.0 + 0.2, 0.0, 1.0)
		drift = clampf(drift, -mag * 2.5, mag * 2.5)
		var horizontal := drift * 0.35 + rng.randf_range(-0.15, 0.15) * mag
		out.append(Vector2(horizontal, vertical))
	return out


## Accumulated kick after `shots` consecutive shots (used for camera punch & compensation).
static func accumulated(pattern: PackedVector2Array, shots: int) -> Vector2:
	var acc := Vector2.ZERO
	for i in range(min(shots, pattern.size())):
		acc += pattern[i]
	return acc
