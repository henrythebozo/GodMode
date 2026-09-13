extends Control
## Tab scoreboard: both teams with K/D/A, score, MVPs, money (own team), ping and status.

var box: VBoxContainer


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var panel := UIKit.panel(Vector2(860, 400))
	add_child(UIKit.centered(panel))
	box = VBoxContainer.new()
	panel.add_child(box)


func _process(_d: float) -> void:
	if not visible:
		return
	for c in box.get_children():
		c.queue_free()
	var m := Match
	box.add_child(UIKit.title("Foundry — %s  |  Round %d  |  %d : %d" % [m.state_name(), m.round_number, m.score[Teams.ATTACKERS], m.score[Teams.DEFENDERS]], 22))
	var lp := Net.local_player()
	for team in [Teams.ATTACKERS, Teams.DEFENDERS]:
		box.add_child(UIKit.label(Teams.team_name(team), UIKit.team_color(team), 18))
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 18)
		box.add_child(grid)
		for h in ["Player", "K", "D", "A", "Score", "MVP", "$", "Ping"]:
			grid.add_child(UIKit.label(h, UIKit.DIM, 13))
		var rows := []
		for id in Net.infos:
			if Net.infos[id].team == team:
				var p: Player = Net.players.get(id)
				var st: Dictionary = p.stats if p else Net.infos[id].get("stats", {})
				rows.append([id, Net.infos[id], p, st])
		rows.sort_custom(func(a, b): return a[3].get("score", 0) > b[3].get("score", 0))
		for r in rows:
			var info: Dictionary = r[1]
			var p: Player = r[2]
			var st: Dictionary = r[3]
			var alive: bool = p.alive if p else info.get("alive", false)
			var name_col := UIKit.TEXT if alive else UIKit.DIM
			var nm: String = info.name + ("  ★" if m.round_mvp_id == r[0] else "") + ("" if info.connected else " (dc)")
			grid.add_child(UIKit.label(nm, name_col))
			grid.add_child(UIKit.label(str(st.get("kills", 0))))
			grid.add_child(UIKit.label(str(st.get("deaths", 0))))
			grid.add_child(UIKit.label(str(st.get("assists", 0))))
			grid.add_child(UIKit.label(str(st.get("score", 0))))
			grid.add_child(UIKit.label(str(st.get("mvps", 0))))
			var show_money: bool = lp != null and (lp.team == team or lp.team == Teams.SPECTATOR)
			grid.add_child(UIKit.label(("$%d" % (p.money if p else info.get("money", 0))) if show_money else "—", UIKit.OK if show_money else UIKit.DIM))
			grid.add_child(UIKit.label("bot" if info.bot else str(info.ping)))
		box.add_child(UIKit.hsep())
