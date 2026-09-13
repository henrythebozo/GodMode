extends Control
## Final results: winner, full scoreboard, rematch vote and return-to-menu.

var scoreboard: Control


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.9)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vb.offset_top = 40
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vb)
	var m := Match
	var t := UIKit.title("%s WIN THE MATCH" % Teams.team_name(m.match_winner).to_upper() if m.match_winner != Teams.NONE else "DRAW", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := UIKit.label("Final score %d : %d%s" % [m.score[Teams.ATTACKERS], m.score[Teams.DEFENDERS], "  (overtime)" if m.overtime else ""], UIKit.DIM, 20)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	scoreboard = load("res://src/ui/Scoreboard.gd").new()
	scoreboard.custom_minimum_size.y = 420
	vb.add_child(scoreboard)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	row.add_child(UIKit.button("REMATCH", func():
		if Net.is_server():
			Match.server_request_rematch(Net.local_id)
		else:
			Net.rpc_id(1, "rpc_request_rematch"), 200))
	if Net.is_server():
		row.add_child(UIKit.button("BACK TO LOBBY", func(): Match.server_return_to_lobby(), 200))
	row.add_child(UIKit.button("MAIN MENU", func(): Events.open_menu.emit("leave"), 200))
