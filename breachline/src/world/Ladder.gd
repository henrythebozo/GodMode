class_name Ladder
extends Area3D
## Climbable volume. Players inside move along the ladder in PlayerBody._simulate_ladder().

var climb_dir := Vector3.FORWARD
var top := Vector3.ZERO


func setup(pos: Vector3, top_pos: Vector3, height: float, dir: Vector3) -> void:
	climb_dir = dir.normalized()
	top = top_pos
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, height + 0.6, 1.2)
	shape.shape = box
	shape.position = Vector3(0, height / 2.0 + 0.2, 0)
	add_child(shape)
	global_position = pos - climb_dir * 0.35
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node) -> void:
	if body is PlayerBody:
		body.ladder_dir = climb_dir
		body.enter_ladder(self)


func _on_exit(body: Node) -> void:
	if body is PlayerBody:
		body.exit_ladder(self)
