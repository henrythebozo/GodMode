class_name Hitboxes
extends RefCounted
## Analytic hurtboxes: capsules/spheres defined in player-local space (Y up, facing -Z).
## Used by the server for lag-compensated ray tests without touching the physics server,
## so rewinding a player is just supplying a different transform.

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.3

## Each zone: {zone, a, b, r}  capsule from a to b with radius r (a == b -> sphere).
static func zones(crouching: bool) -> Array:
	var s := 1.0 if not crouching else CROUCH_HEIGHT / STAND_HEIGHT
	return [
		{"zone": DamageModel.Zone.HEAD, "a": Vector3(0, 1.66 * s, 0), "b": Vector3(0, 1.66 * s, 0), "r": 0.14},
		{"zone": DamageModel.Zone.CHEST, "a": Vector3(0, 1.20 * s, 0), "b": Vector3(0, 1.45 * s, 0), "r": 0.22},
		{"zone": DamageModel.Zone.STOMACH, "a": Vector3(0, 0.95 * s, 0), "b": Vector3(0, 1.15 * s, 0), "r": 0.20},
		{"zone": DamageModel.Zone.ARM, "a": Vector3(-0.30, 1.42 * s, 0), "b": Vector3(-0.34, 0.95 * s, 0), "r": 0.075},
		{"zone": DamageModel.Zone.ARM, "a": Vector3(0.30, 1.42 * s, 0), "b": Vector3(0.34, 0.95 * s, 0), "r": 0.075},
		{"zone": DamageModel.Zone.LEG, "a": Vector3(-0.11, 0.90 * s, 0), "b": Vector3(-0.11, 0.08, 0), "r": 0.11},
		{"zone": DamageModel.Zone.LEG, "a": Vector3(0.11, 0.90 * s, 0), "b": Vector3(0.11, 0.08, 0), "r": 0.11},
	]


## Ray vs all zones of a player at `xform`. Returns {hit:bool, zone:int, distance:float, point:Vector3}.
## Head is tested first so a ray grazing head and chest counts as a headshot.
static func raycast(xform: Transform3D, crouching: bool, origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var best := {"hit": false, "zone": DamageModel.Zone.NONE, "distance": INF, "point": Vector3.ZERO}
	var inv := xform.affine_inverse()
	var lo := inv * origin
	var ld := (inv.basis * dir).normalized()
	for z in zones(crouching):
		var d := _ray_capsule(lo, ld, z.a, z.b, z.r)
		if d >= 0.0 and d <= max_dist and d < best.distance:
			best = {"hit": true, "zone": z.zone, "distance": d, "point": xform * (lo + ld * d)}
			if z.zone == DamageModel.Zone.HEAD:
				break
	return best


## Distance along the ray to the first intersection with a capsule, or -1.
static func _ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ab := b - a
	var best := -1.0
	if ab.length_squared() > 1e-8:
		# infinite cylinder around ab, then clamp to the segment
		var ao := o - a
		var ab_n := ab.normalized()
		var d_perp := d - ab_n * d.dot(ab_n)
		var ao_perp := ao - ab_n * ao.dot(ab_n)
		var qa := d_perp.length_squared()
		var qb := 2.0 * d_perp.dot(ao_perp)
		var qc := ao_perp.length_squared() - r * r
		if qa > 1e-8:
			var disc := qb * qb - 4.0 * qa * qc
			if disc >= 0.0:
				var t := (-qb - sqrt(disc)) / (2.0 * qa)
				if t >= 0.0:
					var p := o + d * t
					var along := (p - a).dot(ab_n)
					if along >= 0.0 and along <= ab.length():
						best = t
	for c in [a, b]:
		var t := _ray_sphere(o, d, c, r)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.length_squared() - r * r
	if cc > 0.0 and b > 0.0:
		return -1.0
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return max(t, 0.0)
