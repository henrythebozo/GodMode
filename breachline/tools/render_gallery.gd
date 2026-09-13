extends SceneTree
## Renders every model GLB into a contact sheet for visual verification (needs a display / Xvfb):
##   xvfb-run -a godot --path breachline --rendering-driver opengl3 -s tools/render_gallery.gd -- --out ../docs/images
## Also renders the first-person arms with a weapon attached exactly like the in-game ViewModel does.

const TILE := 320


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var out_dir := "res://../docs/images"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.get_viewport().size = Vector2i(TILE, TILE)
	var groups := {
		"weapons": _glob("res://assets/models/weapons"),
		"characters": ["res://assets/models/characters/cinder.glb", "res://assets/models/characters/aegis.glb", "tp+cinder+corsair", "tp+aegis+lynx", "fp_arms+p9", "fp_arms+corsair", "fp_arms+knife", "fp_arms+frag"],
		"environment": _glob("res://assets/models/environment"),
	}
	for g in groups:
		var paths: Array = groups[g]
		var cols := 6
		var rows := int(ceil(paths.size() / float(cols)))
		var sheet := Image.create(cols * TILE, rows * TILE, false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.1, 0.1, 0.12))
		for i in paths.size():
			var img := await _render_one(paths[i])
			sheet.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i((i % cols) * TILE, (i / cols) * TILE))
		var path := ProjectSettings.globalize_path("%s/gallery_%s.png" % [out_dir, g])
		sheet.save_png(path)
		print("[gallery] wrote %s (%d assets)" % [path, paths.size()])
	quit()


func _glob(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb"):
			out.append(dir + "/" + f)
	out.sort()
	return out


func _render_one(spec: String) -> Image:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.6
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	var subject: Node3D
	var label := spec.get_file()
	if spec.begins_with("fp_arms+"):
		var wid := spec.split("+")[1]
		subject = _build_fp(wid)
		label = spec
	elif spec.begins_with("tp+"):
		var parts := spec.split("+")
		subject = _build_tp(parts[1], parts[2])
		label = spec
	else:
		subject = load(spec).instantiate()
		for c in subject.find_children("*", "", true, false):
			if c.name.ends_with("_LOD1") or c.name.ends_with("_convcol") or c.name.ends_with("_colonly") or c.name.ends_with("-convcol") or c.name.ends_with("-colonly"):
				c.visible = false
		var anim: AnimationPlayer = subject.find_child("AnimationPlayer", true, false)
		if anim and anim.has_animation("idle"):
			anim.play("idle")
	stage.add_child(subject)
	var aabb := _bounds(subject)
	var cam := Camera3D.new()
	stage.add_child(cam)
	var centre := aabb.get_center()
	var radius: float = max(aabb.size.length() * 0.5, 0.05)
	var dir := Vector3(0.9, 0.5, 1.0).normalized()
	if spec.begins_with("fp_arms+"):
		dir = Vector3(1.0, 0.45, 0.35).normalized()   # side view: forward (-Z) is screen-left
		centre = Vector3(0.05, -0.2, -0.35)
		radius = 0.5
	elif spec.begins_with("tp+"):
		dir = Vector3(-0.6, 0.35, -1.0).normalized()   # three-quarter front view
		centre = Vector3(0, 1.0, 0)
		radius = 1.1
	cam.position = centre + dir * radius * 2.2
	cam.look_at(centre, Vector3.UP)
	cam.fov = 45
	cam.current = true
	# forward marker: small red cone pointing along the model's -Z so orientation is obvious
	var marker := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius * 0.05
	cone.height = radius * 0.2
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.1, 0.1)
	cone.material = mm
	marker.mesh = cone
	marker.position = Vector3(aabb.position.x + aabb.size.x + radius * 0.15, centre.y, aabb.position.z - radius * 0.1)
	marker.rotation_degrees = Vector3(-90, 0, 180)
	stage.add_child(marker)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_stamp(img, label)
	stage.queue_free()
	await process_frame
	return img


func _build_fp(wid: String) -> Node3D:
	var holder := Node3D.new()
	var arms: Node3D = load("res://assets/models/characters/fp_arms.glb").instantiate()
	holder.add_child(arms)
	var skel: Skeleton3D = arms.find_child("Skeleton3D", true, false)
	var att := BoneAttachment3D.new()
	att.bone_name = "weapon"
	skel.add_child(att)
	var wh := Node3D.new()
	wh.rotation_degrees = Vector3(-90, 0, 180)
	att.add_child(wh)
	var w := WeaponMeshFactory.instantiate_weapon(wid, true)
	if w:
		wh.add_child(w)
	var anim: AnimationPlayer = arms.find_child("AnimationPlayer", true, false)
	if anim:
		anim.play("idle")
	return holder


func _build_tp(faction: String, wid: String) -> Node3D:
	var holder := Node3D.new()
	var body: Node3D = load("res://assets/models/characters/%s.glb" % faction).instantiate()
	holder.add_child(body)
	for c in body.find_children("*_LOD1", "", true, false):
		c.visible = false
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	var att := BoneAttachment3D.new()
	att.bone_name = "weapon_r"
	skel.add_child(att)
	var wh := Node3D.new()
	wh.rotation_degrees = Vector3(-90, 0, 180)
	att.add_child(wh)
	var w := WeaponMeshFactory.instantiate_weapon(wid, false)
	if w:
		wh.add_child(w)
	var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	if anim:
		anim.play("idle")
	return holder


func _bounds(n: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb if not first else AABB(Vector3.ZERO, Vector3.ONE)


func _stamp(img: Image, text: String) -> void:
	# simple 3x5 pixel font is overkill; draw a dark strip and rely on the file order + printed list
	for y in range(img.get_height() - 14, img.get_height()):
		for x in range(img.get_width()):
			img.set_pixel(x, y, Color(0, 0, 0))
	print("[gallery] tile: " + text)
