extends Node3D
## Client-side beeping/flashing for the planted bomb; accelerates as the timer runs down.

var t := 0.0
var light: OmniLight3D


func _ready() -> void:
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.1, 0.1)
	light.light_energy = 0.0
	light.omni_range = 3.0
	light.position = Vector3(0, 0.3, 0)
	add_child(light)


func _process(delta: float) -> void:
	var remaining: float = Match.bomb_timer
	var interval := clampf(remaining / Match.rules.bomb_timer, 0.06, 1.0) * 0.9 + 0.08
	t += delta
	light.light_energy = max(light.light_energy - delta * 12.0, 0.0)
	if t >= interval:
		t = 0.0
		light.light_energy = 3.0
		Audio.play_3d("grenades/bomb_beep.wav", global_position, -2.0, 1.0 + (1.0 - remaining / Match.rules.bomb_timer) * 0.4, 60.0)
