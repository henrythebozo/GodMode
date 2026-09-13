class_name AreaEffect
extends Node3D
## Lingering grenade effect (smoke or fire). Server keeps timing + fire damage; clients render.

const TYPE_AREA := 2

var kind := "smoke"
var radius := 4.0
var remaining := 10.0
var owner_id := 0
var owner_team := 0
var entity_id := 0
var is_server_side := false
var visual: Node3D
var damage_tick := 0.0
var loop_player: AudioStreamPlayer3D


func setup(k: String, r: float, duration: float, owner: int, team: int, server_side: bool) -> void:
	kind = k
	radius = r
	remaining = duration
	owner_id = owner
	owner_team = team
	is_server_side = server_side
	if DisplayServer.get_name() != "headless" and Fx.instance:
		if kind == "smoke":
			visual = Fx.instance.smoke_cloud(global_position, radius, duration)
			Audio.play_3d("grenades/smoke_pop.wav", global_position, -4.0)
			_loop("grenades/smoke_loop.wav", -14.0)
		else:
			visual = Fx.instance.fire_area(global_position, radius, duration)
			Audio.play_3d("grenades/fire_ignite.wav", global_position, -2.0)
			_loop("grenades/fire_loop.wav", -8.0)


func _loop(clip: String, db: float) -> void:
	var s := Audio.stream(clip)
	if s == null:
		return
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = s.data.size() / 2
	loop_player = AudioStreamPlayer3D.new()
	loop_player.stream = s
	loop_player.volume_db = db
	loop_player.max_distance = 40.0
	loop_player.bus = "SFX"
	add_child(loop_player)
	loop_player.play()


func blocks_sight(a: Vector3, b: Vector3) -> bool:
	if kind != "smoke":
		return false
	# segment-sphere test against the smoke volume
	var c := global_position + Vector3(0, radius * 0.5, 0)
	var ab := b - a
	var t := clampf((c - a).dot(ab) / max(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < radius * 0.9


func _physics_process(delta: float) -> void:
	remaining -= delta
	if not is_server_side:
		return
	if kind == "fire":
		damage_tick -= delta
		if damage_tick <= 0.0:
			damage_tick = 0.25
			var cfg := WeaponDB.get_config("incendiary")
			for p: Player in Net.players.values():
				if not p.alive:
					continue
				if not Match.rules.friendly_fire and p.team == owner_team and p.peer_id != owner_id:
					continue
				var d: float = Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
				if d < radius and abs(p.global_position.y - global_position.y) < 2.0:
					p.server_apply_damage(int(cfg.effect_power * 0.25), 0, owner_id, cfg.id, DamageModel.Zone.LEG, Vector3.UP, false)
	if remaining <= 0.0:
		Net.server_despawn_entity(entity_id)
