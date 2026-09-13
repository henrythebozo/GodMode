class_name WeaponPickup
extends RigidBody3D
## Dropped weapon / bomb on the ground. Server-simulated; clients mirror position from snapshots.

const TYPE_PICKUP := 3

var weapon_id := ""
var entity_id := 0
var ammo := 0
var reserve := 0
var is_server_side := false
var mesh_root: Node3D
var pickup_area: Area3D
var settle_time := 0.0


func setup(id: String, a: int, r: int, server_side: bool) -> void:
	weapon_id = id
	ammo = a
	reserve = r
	is_server_side = server_side
	collision_layer = 16
	collision_mask = 1
	mass = 2.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 0.12, 0.6)
	shape.shape = box
	add_child(shape)
	if not server_side:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	mesh_root = WeaponMeshFactory.instantiate_weapon(id, false)
	if mesh_root:
		add_child(mesh_root)
	if server_side:
		pickup_area = Area3D.new()
		pickup_area.collision_layer = 0
		pickup_area.collision_mask = 2
		var s := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.9
		s.shape = sph
		pickup_area.add_child(s)
		add_child(pickup_area)
		pickup_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	settle_time += delta
	if is_server_side and settle_time > 0.4 and pickup_area:
		for b in pickup_area.get_overlapping_bodies():
			_on_body_entered(b)


func _on_body_entered(body: Node) -> void:
	if not is_server_side or settle_time < 0.4:
		return
	if body is Player and body.alive:
		Net.server_try_auto_pickup(body, self)
