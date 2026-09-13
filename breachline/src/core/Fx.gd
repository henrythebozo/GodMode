class_name Fx
extends Node3D
## Client-side effects: muzzle flash, tracers, impacts, decals, shells, blood. One instance lives in
## the world scene; everything here is fire-and-forget and respects the blood/reduced-motion settings.

static var instance: Fx
static var _decal_tex: Texture2D
static var _tracer_mesh: Mesh
static var _shell_scene: PackedScene
var _decals: Array = []
const MAX_DECALS := 200


func _ready() -> void:
	instance = self
	_shell_scene = load("res://assets/models/weapons/shell_casing.glb") if ResourceLoader.exists("res://assets/models/weapons/shell_casing.glb") else null


static func decal_texture() -> Texture2D:
	if _decal_tex:
		return _decal_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(0.05, 0.04, 0.03, a * (0.9 if d < 0.5 else 0.6)))
	_decal_tex = ImageTexture.create_from_image(img)
	return _decal_tex


static func tracer_mesh() -> Mesh:
	if _tracer_mesh:
		return _tracer_mesh
	var m := CylinderMesh.new()
	m.top_radius = 0.008
	m.bottom_radius = 0.008
	m.height = 1.0
	m.radial_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	m.material = mat
	_tracer_mesh = m
	return _tracer_mesh


func muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.0
	light.omni_range = 4.0
	light.position = pos
	add_child(light)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.8, 0.4, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 4.0
	qm.material = mat
	quad.mesh = qm
	quad.position = pos + dir * 0.05
	add_child(quad)
	_expire([light, quad], 0.05)


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = tracer_mesh()
	var start := from.lerp(to, 0.15)
	var mid := (start + to) * 0.5
	mi.position = mid
	mi.scale = Vector3(1, length * 0.85, 1)
	var dir := (to - from).normalized()
	var up := Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.basis = Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI / 2.0)
	add_child(mi)
	_expire([mi], 0.06)


func impact(pos: Vector3, normal: Vector3, kind: int, is_metal: bool = false) -> void:
	if kind == Player.IMPACT_PLAYER or kind == Player.IMPACT_HEADSHOT:
		if bool(Settings.get_value("accessibility", "blood", true)):
			_burst(pos, Color(0.55, 0.05, 0.05), 14, 2.0, 0.35)
		else:
			_burst(pos, Color(0.9, 0.9, 0.8), 6, 1.0, 0.2)
		Audio.play_3d("weapons/bullet_impact_flesh.wav", pos, -6.0)
		return
	_burst(pos, Color(0.75, 0.7, 0.6), 10, 3.0, 0.3)
	Audio.play_3d("weapons/bullet_impact_metal.wav" if is_metal else "weapons/bullet_impact_concrete.wav", pos, -8.0, randf_range(0.9, 1.1), 40.0)
	var d := Decal.new()
	d.texture_albedo = decal_texture()
	d.size = Vector3(0.12, 0.2, 0.12)
	d.cull_mask = 1
	d.position = pos + normal * 0.01
	var up := Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	d.basis = Basis.looking_at(-normal, up) * Basis(Vector3.RIGHT, PI / 2.0)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	add_child(d)
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		var old: Node = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _burst(pos: Vector3, color: Color, count: int, speed: float, life: float) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	p.draw_pass_1 = bm
	p.position = pos
	add_child(p)
	_expire([p], life + 0.2)


func eject_shell(xform: Transform3D) -> void:
	if _shell_scene == null:
		return
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.01
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.01
	shape.shape = s
	body.add_child(shape)
	var mesh := _shell_scene.instantiate()
	body.add_child(mesh)
	body.transform = xform
	add_child(body)
	body.linear_velocity = xform.basis.x * randf_range(1.5, 2.5) + Vector3.UP * randf_range(1.0, 2.0) + xform.basis.z * randf_range(-0.3, 0.3)
	body.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(func(): if is_instance_valid(body): Audio.play_3d("weapons/shell_drop.wav", body.global_position, -14.0, randf_range(0.9, 1.15), 15.0))
	_expire([body], 4.0)


func explosion(pos: Vector3, radius: float, color: Color = Color(1.0, 0.6, 0.2)) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = radius * 2.0
	light.position = pos
	add_child(light)
	_burst(pos, color, 40, radius * 1.5, 0.8)
	_burst(pos, Color(0.2, 0.2, 0.2), 30, radius * 0.6, 1.6)
	_expire([light], 0.25)


func smoke_cloud(pos: Vector3, radius: float, duration: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	for i in 9:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * randf_range(0.55, 0.8)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.82, 0.82, 0.85, 0.96)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 1.0
		sm.material = mat
		mi.mesh = sm
		mi.position = Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)) * radius * 0.5
		root.add_child(mi)
	_expire([root], duration)
	return root


func fire_area(pos: Vector3, radius: float, duration: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.1)
	light.light_energy = 4.0
	light.omni_range = radius * 2.5
	light.position.y = 0.5
	root.add_child(light)
	var p := GPUParticles3D.new()
	p.amount = 80
	p.lifetime = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	p.draw_pass_1 = bm
	root.add_child(p)
	_expire([root], duration)
	return root


func _expire(nodes: Array, seconds: float) -> void:
	var t := get_tree().create_timer(seconds)
	t.timeout.connect(func():
		for n in nodes:
			if is_instance_valid(n):
				n.queue_free())
