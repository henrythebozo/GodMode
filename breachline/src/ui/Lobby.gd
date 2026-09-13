extends Control
## Pre-match lobby: team selection, ready check, bots, match settings (host), start.

var attackers_box: VBoxContainer
var defenders_box: VBoxContainer
var spectators_box: VBoxContainer
var ready_btn: Button
var start_btn: Button
var info: Label
var bots_spin: SpinBox
var diff_opt: OptionButton
var rounds_opt: OptionButton


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 0.92)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_top = 30
	root.offset_right = -40
	root.offset_bottom = -30
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(UIKit.title("LOBBY — Foundry", 36))
	info = UIKit.label("", UIKit.DIM)
	root.add_child(info)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 20)
	teams.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(teams)
	attackers_box = _team_column(teams, Teams.ATTACKERS)
	defenders_box = _team_column(teams, Teams.DEFENDERS)
	spectators_box = _team_column(teams, Teams.SPECTATOR)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	root.add_child(controls)
	ready_btn = UIKit.button("READY", _toggle_ready, 160)
	controls.add_child(ready_btn)
	if Net.is_server():
		controls.add_child(UIKit.label("Bots per team"))
		bots_spin = SpinBox.new()
		bots_spin.min_value = 0
		bots_spin.max_value = 5
		bots_spin.value = int(Settings.get_value("gameplay", "bots_per_team", 4))
		controls.add_child(bots_spin)
		controls.add_child(UIKit.button("FILL BOTS", _fill_bots, 140))
		controls.add_child(UIKit.button("KICK BOTS", func(): Net.server_remove_bots(), 140))
		controls.add_child(UIKit.label("Difficulty"))
		diff_opt = OptionButton.new()
		for d in ["Easy", "Normal", "Hard", "Expert"]:
			diff_opt.add_item(d)
		diff_opt.selected = int(Settings.get_value("gameplay", "bot_difficulty", 1))
		diff_opt.item_selected.connect(func(i): Settings.set_value("gameplay", "bot_difficulty", i); DebugConsole.execute("bot_difficulty %d" % i))
		controls.add_child(diff_opt)
		controls.add_child(UIKit.label("Rounds"))
		rounds_opt = OptionButton.new()
		for r in [6, 12, 16, 24, 30]:
			rounds_opt.add_item(str(r))
		rounds_opt.selected = [6, 12, 16, 24, 30].find(int(Settings.get_value("gameplay", "max_rounds", 24)))
		rounds_opt.item_selected.connect(func(i): Settings.set_value("gameplay", "max_rounds", [6, 12, 16, 24, 30][i]))
		controls.add_child(rounds_opt)
		start_btn = UIKit.button("START MATCH", func(): Match.server_start_match(), 180)
		controls.add_child(start_btn)
	controls.add_child(UIKit.button("SETTINGS", func(): Events.open_menu.emit("settings"), 130))
	controls.add_child(UIKit.button("LEAVE", func(): Events.open_menu.emit("leave"), 130))
	Events.lobby_updated.connect(_refresh)
	Events.connection_state_changed.connect(func(s, d): info.text = "%s — %s" % [s, d])
	_refresh()


func _team_column(parent: Control, team: int) -> VBoxContainer:
	var panel := UIKit.panel(Vector2(300, 300))
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var t := UIKit.label(Teams.team_name(team), UIKit.team_color(team), 22)
	vb.add_child(t)
	vb.add_child(UIKit.label({Teams.ATTACKERS: "Attackers — plant the charge", Teams.DEFENDERS: "Defenders — hold the sites", Teams.SPECTATOR: "Watch only"}[team], UIKit.DIM))
	vb.add_child(UIKit.button("JOIN", func(): _join_team(team), 120))
	vb.add_child(UIKit.hsep())
	var list := VBoxContainer.new()
	vb.add_child(list)
	return list


func _join_team(team: int) -> void:
	if Net.is_server():
		Net.server_set_team(Net.local_id, team)
	else:
		Net.rpc_id(1, "rpc_set_team", team)


func _toggle_ready() -> void:
	var me: Dictionary = Net.infos.get(Net.local_id, {})
	var r: bool = not me.get("ready", false)
	if Net.is_server():
		Net.server_set_ready(Net.local_id, r)
	else:
		Net.rpc_id(1, "rpc_ready", r)


func _fill_bots() -> void:
	var per_team := int(bots_spin.value)
	Settings.set_value("gameplay", "bots_per_team", per_team)
	for team in [Teams.ATTACKERS, Teams.DEFENDERS]:
		var humans := 0
		var bots := 0
		for i: Dictionary in Net.infos.values():
			if i.team == team:
				if i.bot:
					bots += 1
				else:
					humans += 1
		var want: int = clampi(per_team, 0, Match.rules.team_size - humans)
		while bots < want:
			Net.server_add_bot(team, int(Settings.get_value("gameplay", "bot_difficulty", 1)))
			bots += 1


func _refresh() -> void:
	for box in [attackers_box, defenders_box, spectators_box]:
		for c in box.get_children():
			c.queue_free()
	var ids := Net.infos.keys()
	ids.sort()
	for id in ids:
		var i: Dictionary = Net.infos[id]
		var box: VBoxContainer = {Teams.ATTACKERS: attackers_box, Teams.DEFENDERS: defenders_box}.get(i.team, spectators_box)
		var txt := "%s%s%s" % [i.name, "  ✓" if i.ready else "", "" if i.connected else "  (reconnecting)"]
		if id == Net.local_id:
			txt = "▶ " + txt
		var l := UIKit.label(txt, UIKit.OK if i.ready else UIKit.TEXT)
		box.add_child(l)
	var me: Dictionary = Net.infos.get(Net.local_id, {})
	ready_btn.text = "UNREADY" if me.get("ready", false) else "READY"
	if Net.is_server():
		info.text = "Hosting on port %d — %d players. Everyone ready or START MATCH begins the game." % [Net.listen_port, Net.infos.size()]
