extends Control
## Configurable crosshair; expands with the active weapon's current inaccuracy when dynamic.

var preview := false
var spread_px := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if not preview:
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if preview:
		return
	var lp := Net.local_player()
	var target := 0.0
	if lp and lp.alive:
		var w := lp.active_weapon()
		if w and w.cfg.is_firearm():
			var deg := w.inaccuracy(lp.horizontal_speed(), lp.crouching, not lp.is_on_floor(), lp.on_ladder, lp.zoomed)
			target = clampf(deg * 6.0, 0.0, 60.0)
	spread_px = lerpf(spread_px, target, 0.3)
	queue_redraw()


func _draw() -> void:
	var ch: Dictionary = Settings.get_value("player", "crosshair", {})
	var c := size / 2.0
	var len := float(ch.get("size", 6.0))
	var gap := float(ch.get("gap", 3.0)) + (spread_px if bool(ch.get("dynamic", true)) else 0.0)
	var th := float(ch.get("thickness", 2.0))
	var color := Color(str(ch.get("color", "00ff66")))
	var lp := Net.local_player()
	if lp and lp.zoomed and lp.active_config() and lp.active_config().category == "sniper" and not preview:
		draw_circle(c, 140.0, Color(0, 0, 0, 0.0))
		draw_arc(c, 150.0, 0, TAU, 96, Color(0, 0, 0, 1), 260.0)
		draw_line(c - Vector2(150, 0), c + Vector2(150, 0), Color(0, 0, 0), 1.5)
		draw_line(c - Vector2(0, 150), c + Vector2(0, 150), Color(0, 0, 0), 1.5)
		return
	var segs := [[Vector2(-gap - len, 0), Vector2(-gap, 0)], [Vector2(gap, 0), Vector2(gap + len, 0)], [Vector2(0, gap), Vector2(0, gap + len)]]
	if not bool(ch.get("t_style", false)):
		segs.append([Vector2(0, -gap - len), Vector2(0, -gap)])
	for s in segs:
		if bool(ch.get("outline", true)):
			draw_line(c + s[0], c + s[1], Color.BLACK, th + 2.0)
		draw_line(c + s[0], c + s[1], color, th)
	if bool(ch.get("dot", false)):
		if bool(ch.get("outline", true)):
			draw_circle(c, th + 1.0, Color.BLACK)
		draw_circle(c, th, color)
