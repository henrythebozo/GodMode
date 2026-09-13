extends Control
## Escape menu: resume, settings, team change, surrender vote, leave.


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var panel := UIKit.panel(Vector2(320, 0))
	add_child(UIKit.centered(panel))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(UIKit.title("PAUSED", 28))
	vb.add_child(UIKit.label("The match keeps running.", UIKit.DIM, 13))
	vb.add_child(UIKit.button("RESUME", func(): Events.open_menu.emit("close_pause"), 280))
	vb.add_child(UIKit.button("SETTINGS", func(): Events.open_menu.emit("settings"), 280))
	vb.add_child(UIKit.button("JOIN ATTACKERS", func(): _team(Teams.ATTACKERS), 280))
	vb.add_child(UIKit.button("JOIN DEFENDERS", func(): _team(Teams.DEFENDERS), 280))
	vb.add_child(UIKit.button("SPECTATE", func(): _team(Teams.SPECTATOR), 280))
	vb.add_child(UIKit.button("CALL SURRENDER VOTE", func():
		if Net.is_server():
			Match.server_vote_surrender(Net.local_id, true)
		else:
			Net.rpc_id(1, "rpc_vote_surrender", true)
		Events.open_menu.emit("close_pause"), 280))
	if Net.is_server():
		vb.add_child(UIKit.button("RETURN TO LOBBY", func(): Match.server_return_to_lobby(); Events.open_menu.emit("close_pause"), 280))
	vb.add_child(UIKit.button("LEAVE MATCH", func(): Events.open_menu.emit("leave"), 280))


func _team(t: int) -> void:
	if Net.is_server():
		Net.server_set_team(Net.local_id, t)
	else:
		Net.rpc_id(1, "rpc_set_team", t)
	Events.open_menu.emit("close_pause")
