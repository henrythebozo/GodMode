class_name Grenade
extends RigidBody3D
## Server-simulated grenade projectile. Clients mirror position from snapshots and render the
## detonation from a reliable entity event. Effect logic lives in server_detonate().

const TYPE_GRENADE := 1

var cfg: WeaponConfig
var owner_id: int = 0
var owner_team: int = 0
var entity_id: int = 0
var fuse: float = 1.5
var is_server_side := false
var detonated := false
var mesh_root: Node3D
var decoy_timer := 0.0
var decoy_shots := 0
var effect_node: Node3D
var bounce_cooldown := 0.0


func setup(config: WeaponConfig, owner: int, team: int, server_side: bool) -> void:
	cfg = config
	owner_id = owner
	owner_team = team
	is_server_side = server_side
	fuse = config.fuse_time
	mass = 0.4
	collision_layer = 4
	collision_mask = 1 | 4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.06
	shape.shape = s
	add_child(shape)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	if not server_side:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	mesh_root = WeaponMeshFactory.instantiate_weapon(cfg.id, false)
	if mesh_root:
		add_child(mesh_root)
	body_entered.connect(_on_body_entered)


func _on_body_entered(_body: Node) -> void:
	if bounce_cooldown <= 0.0 and linear_velocity.length() > 2.0:
		bounce_cooldown = 0.2
		Net.server_entity_event(entity_id, "bounce", {"p": global_position})


func _physics_process(delta: float) -> void:
	bounce_cooldown -= delta
	if not is_server_side or detonated:
		return
	fuse -= delta
	if cfg.id == "decoy" and fuse <= 0.0:
		return
	if fuse <= 0.0:
		server_detonate()


func server_detonate() -> void:
	if detonated:
		return
	detonated = true
	var pos := global_position
	match cfg.id:
		"frag":
			_frag_damage(pos)
			Net.server_entity_event(entity_id, "detonate", {"p": pos, "kind": "frag"})
			Net.server_despawn_entity(entity_id)
		"flash":
			_flash_players(pos)
			Net.server_entity_event(entity_id, "detonate", {"p": pos, "kind": "flash"})
			Net.server_despawn_entity(entity_id)
		"smoke":
			Net.server_spawn_area_effect("smoke", pos, cfg.effect_radius, cfg.effect_duration, owner_id, owner_team)
			Net.server_despawn_entity(entity_id)
		"incendiary":
			Net.server_spawn_area_effect("fire", pos, cfg.effect_radius, cfg.effect_duration, owner_id, owner_team)
			Net.server_despawn_entity(entity_id)
		"decoy":
			# decoy keeps living: it emits fake gunfire for effect_duration then pops
			detonated = false
			decoy_timer = 0.0


func _process(delta: float) -> void:
	if not is_server_side or cfg.id != "decoy" or fuse > 0.0:
		return
	decoy_timer -= delta
	if decoy_timer <= 0.0:
		decoy_timer = randf_range(0.4, 1.4)
		decoy_shots += 1
		Net.server_entity_event(entity_id, "decoy_shot", {"p": global_position})
		Match.server_report_noise(global_position, owner_team, "gunfire")
		if decoy_shots * 0.9 > cfg.effect_duration:
			detonated = true
			Net.server_entity_event(entity_id, "detonate", {"p": global_position, "kind": "decoy"})
			Net.server_despawn_entity(entity_id)


func _frag_damage(pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	for p: Player in Net.players.values():
		if not p.alive:
			continue
		if not Match.rules.friendly_fire and p.team == owner_team and p.peer_id != owner_id:
			continue
		var target: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		var dist := pos.distance_to(target)
		if dist > cfg.effect_radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, target, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			dist *= 1.6   # partial cover: treat as further away
		var res := DamageModel.explosion(cfg, dist, p.armor)
		if res.damage > 0:
			p.server_apply_damage(res.damage, res.armor_damage, owner_id, cfg.id, DamageModel.Zone.CHEST, (target - pos).normalized(), res.armor_hit)


func _flash_players(pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	for p: Player in Net.players.values():
		if not p.alive:
			continue
		var eye: Vector3 = p.eye_position()
		var dist := pos.distance_to(eye)
		if dist > cfg.effect_radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, eye, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var to_flash := (pos - eye).normalized()
		var facing: float = p.aim_direction().dot(to_flash)     # 1 = looking straight at it
		var angle_factor := clampf((facing + 0.3) / 1.3, 0.0, 1.0)
		var dist_factor := 1.0 - dist / cfg.effect_radius
		var strength := clampf(angle_factor * 0.85 + dist_factor * 0.35, 0.0, 1.0)
		if strength < 0.08:
			continue
		var duration := cfg.effect_duration * strength
		Net.server_flash_player(p, strength, duration)
