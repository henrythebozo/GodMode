extends Control
## Brief round summary shown during ROUND_END.

var lbl: Label
var sub: Label


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	mouse_filter = MOUSE_FILTER_IGNORE
	offset_top = 130
	offset_left = -300
	offset_right = 300
	var panel := UIKit.panel()
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	lbl = UIKit.label("", UIKit.ACCENT, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	sub = UIKit.label("", UIKit.DIM, 15)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)


func _process(_d: float) -> void:
	var m := Match
	visible = m.state == m.State.ROUND_END or m.state == m.State.HALFTIME
	if not visible:
		return
	if m.state == m.State.HALFTIME:
		lbl.text = "HALFTIME"
		sub.text = "Teams switch sides. Score %d : %d" % [m.score[Teams.ATTACKERS], m.score[Teams.DEFENDERS]]
		return
	lbl.text = "%s WIN" % Teams.team_name(m.round_winner).to_upper()
	lbl.add_theme_color_override("font_color", UIKit.team_color(m.round_winner))
	var reason := {"elimination": "Enemy team eliminated", "bomb_exploded": "The charge detonated", "bomb_defused": "The charge was defused", "time": "Time ran out", "surrender": "Surrender"}.get(m.round_end_reason, m.round_end_reason)
	var mvp: String = str(Net.infos.get(m.round_mvp_id, {}).get("name", ""))
	sub.text = reason + ("   |   MVP: %s" % mvp if mvp != "" else "")
