extends Control
## In-game HUD. Reads Player/Match state every frame and reacts to Events for feed items.

var health_lbl: Label
var armor_lbl: Label
var ammo_lbl: Label
var weapon_lbl: Label
var money_lbl: Label
var timer_lbl: Label
var score_lbl: Label
var round_lbl: Label
var state_lbl: Label
var bomb_lbl: Label
var progress: ProgressBar
var progress_lbl: Label
var killfeed: VBoxContainer
var notify_lbl: Label
var chat_box: RichTextLabel
var chat_edit: LineEdit
var crosshair: Control
var hitmarker_t := 0.0
var hitmarker_head := false
var flash_rect: ColorRect
var flash_strength := 0.0
var flash_time := 0.0
var flash_total := 1.0
var damage_indicators: Array = []
var latency_lbl: Label
var callout_lbl: Label
var spectator_lbl: Label
var buyhint_lbl: Label
var inventory_box: HBoxContainer
var team_alive_lbl: Label
var subtitle_lbl: Label
var chat_team_only := false
var notify_t := 0.0
var damage_overlay: ColorRect
var low_hp_pulse := 0.0
var surrender_lbl: Label


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(func(): set_anchors_and_offsets_preset(PRESET_FULL_RECT))
	crosshair = load("res://src/ui/Crosshair.gd").new()
	add_child(crosshair)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	flash_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(flash_rect)
	damage_overlay = ColorRect.new()
	damage_overlay.color = Color(0.8, 0, 0, 0)
	damage_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	damage_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(damage_overlay)
	# bottom-left: health/armor
	var bl := HBoxContainer.new()
	bl.set_anchors_preset(PRESET_BOTTOM_LEFT)
	bl.offset_left = 24
	bl.offset_top = -70
	bl.add_theme_constant_override("separation", 24)
	add_child(bl)
	health_lbl = UIKit.label("100", UIKit.TEXT, 36)
	armor_lbl = UIKit.label("0", UIKit.ACCENT2, 28)
	bl.add_child(UIKit.label("HP", UIKit.DIM))
	bl.add_child(health_lbl)
	bl.add_child(UIKit.label("ARMOR", UIKit.DIM))
	bl.add_child(armor_lbl)
	# bottom-right: weapon/ammo/money
	var br := VBoxContainer.new()
	br.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	br.offset_left = -360
	br.offset_top = -120
	br.offset_right = -24
	br.alignment = BoxContainer.ALIGNMENT_END
	add_child(br)
	money_lbl = UIKit.label("$800", UIKit.OK, 22)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(money_lbl)
	weapon_lbl = UIKit.label("", UIKit.DIM, 16)
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(weapon_lbl)
	ammo_lbl = UIKit.label("", UIKit.TEXT, 36)
	ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(ammo_lbl)
	inventory_box = HBoxContainer.new()
	inventory_box.alignment = BoxContainer.ALIGNMENT_END
	br.add_child(inventory_box)
	# top-center: timer & score
	var tc := VBoxContainer.new()
	tc.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	tc.offset_left = -160
	tc.offset_right = 160
	tc.offset_top = 10
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(tc)
	score_lbl = UIKit.label("0 : 0", UIKit.TEXT, 28)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(score_lbl)
	timer_lbl = UIKit.label("1:55", UIKit.TEXT, 26)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(timer_lbl)
	round_lbl = UIKit.label("Round 1", UIKit.DIM, 14)
	round_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(round_lbl)
	team_alive_lbl = UIKit.label("", UIKit.DIM, 14)
	team_alive_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(team_alive_lbl)
	state_lbl = UIKit.label("", UIKit.ACCENT, 18)
	state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(state_lbl)
	bomb_lbl = UIKit.label("", UIKit.BAD, 18)
	bomb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(bomb_lbl)
	# top-right: killfeed + latency
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(PRESET_TOP_RIGHT)
	tr.offset_left = -420
	tr.offset_right = -20
	tr.offset_top = 12
	add_child(tr)
	latency_lbl = UIKit.label("", UIKit.DIM, 13)
	latency_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(latency_lbl)
	killfeed = VBoxContainer.new()
	tr.add_child(killfeed)
	# top-left: callout, chat
	var tl := VBoxContainer.new()
	tl.set_anchors_preset(PRESET_TOP_LEFT)
	tl.offset_left = 20
	tl.offset_top = 12
	tl.offset_right = 480
	add_child(tl)
	callout_lbl = UIKit.label("", UIKit.DIM, 14)
	tl.add_child(callout_lbl)
	chat_box = RichTextLabel.new()
	chat_box.bbcode_enabled = true
	chat_box.scroll_following = true
	chat_box.custom_minimum_size = Vector2(460, 150)
	chat_box.mouse_filter = MOUSE_FILTER_IGNORE
	tl.add_child(chat_box)
	chat_edit = LineEdit.new()
	chat_edit.visible = false
	chat_edit.placeholder_text = "chat (Enter to send, Esc to cancel)"
	chat_edit.text_submitted.connect(_send_chat)
	tl.add_child(chat_edit)
	# center messages
	var cm := VBoxContainer.new()
	cm.set_anchors_preset(PRESET_CENTER)
	cm.offset_left = -300
	cm.offset_right = 300
	cm.offset_top = 80
	cm.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(cm)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(300, 14)
	progress.visible = false
	progress.show_percentage = false
	cm.add_child(progress)
	progress_lbl = UIKit.label("", UIKit.TEXT, 16)
	progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.add_child(progress_lbl)
	notify_lbl = UIKit.label("", UIKit.ACCENT, 20)
	notify_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.add_child(notify_lbl)
	buyhint_lbl = UIKit.label("", UIKit.DIM, 14)
	buyhint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.add_child(buyhint_lbl)
	spectator_lbl = UIKit.label("", UIKit.TEXT, 18)
	spectator_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.add_child(spectator_lbl)
	surrender_lbl = UIKit.label("", UIKit.ACCENT2, 16)
	surrender_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.add_child(surrender_lbl)
	subtitle_lbl = UIKit.label("", UIKit.TEXT, 16)
	subtitle_lbl.set_anchors_preset(PRESET_CENTER_BOTTOM)
	subtitle_lbl.offset_top = -150
	subtitle_lbl.offset_left = -400
	subtitle_lbl.offset_right = 400
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(subtitle_lbl)
	Events.player_killed.connect(_on_kill)
	Events.hit_confirmed.connect(_on_hit)
	Events.player_damaged.connect(_on_damaged)
	Events.flashed.connect(_on_flashed)
	Events.notification.connect(_on_notify)
	Events.chat_message.connect(_on_chat)
	Events.latency_updated.connect(func(ms): latency_lbl.text = "%d ms" % ms if bool(Settings.get_value("network", "show_latency", true)) else "")
	Events.spectating_changed.connect(_on_spectating)
	Events.surrender_vote_updated.connect(func(team, yes, needed): surrender_lbl.text = "Surrender vote: %d/%d (F1 yes / F2 no)" % [yes, needed])
	Events.surrender_vote_started.connect(func(team): surrender_lbl.text = "Surrender vote started — F1 yes / F2 no")
	Events.round_started.connect(func(_r): surrender_lbl.text = "")


func _input(event: InputEvent) -> void:
	if chat_edit.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
		return
	if Net.local_controller and Net.local_controller.ui_blocking:
		return
	if event.is_action_pressed("chat"):
		chat_team_only = Input.is_key_pressed(KEY_SHIFT)
		chat_edit.visible = true
		chat_edit.placeholder_text = "team chat" if chat_team_only else "chat"
		chat_edit.grab_focus()
		Net.local_controller.set_ui_blocking(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_vote(true)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_vote(false)


func _vote(yes: bool) -> void:
	if Net.is_server():
		Match.server_vote_surrender(Net.local_id, yes)
	else:
		Net.rpc_id(1, "rpc_vote_surrender", yes)


func _send_chat(text: String) -> void:
	if not text.strip_edges().is_empty():
		if Net.is_server():
			Net.server_chat(Net.local_id, text, chat_team_only)
		else:
			Net.rpc_id(1, "rpc_chat", text, chat_team_only)
	_close_chat()


func _close_chat() -> void:
	chat_edit.text = ""
	chat_edit.visible = false
	Net.local_controller.set_ui_blocking(false)


func _on_chat(sender: int, team_only: bool, text: String) -> void:
	var info: Dictionary = Net.infos.get(sender, {"name": "?", "team": 0})
	var col := UIKit.team_color(info.team)
	chat_box.append_text("[color=#%s]%s%s:[/color] %s\n" % [col.to_html(false), "(team) " if team_only else "", info.name, text])


func _on_kill(victim: int, killer: int, weapon: String, headshot: bool, assist: int) -> void:
	var vi: Dictionary = Net.infos.get(victim, {"name": "?", "team": 0})
	var ki: Dictionary = Net.infos.get(killer, {"name": "world", "team": 0})
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.mouse_filter = MOUSE_FILTER_IGNORE
	var kc := UIKit.team_color(ki.team).to_html(false)
	var vc := UIKit.team_color(vi.team).to_html(false)
	var wname := WeaponDB.get_config(weapon).display_name if WeaponDB.has(weapon) else weapon
	var assist_txt := ""
	if assist != 0 and Net.infos.has(assist):
		assist_txt = " + [color=#%s]%s[/color]" % [kc, Net.infos[assist].name]
	l.text = "[right][color=#%s]%s[/color]%s  [%s%s]  [color=#%s]%s[/color][/right]" % [kc, ki.name, assist_txt, wname, " ☠HS" if headshot else "", vc, vi.name]
	killfeed.add_child(l)
	get_tree().create_timer(float(Settings.get_value("gameplay", "killfeed_time", 6.0))).timeout.connect(func(): if is_instance_valid(l): l.queue_free())
	if victim == Net.local_id:
		var msg := "You were killed by %s" % ki.name if killer != Net.local_id else "You died"
		_on_notify(msg, 4.0)


func _on_hit(_victim: int, amount: int, headshot: bool, _killed: bool) -> void:
	hitmarker_t = 0.18
	hitmarker_head = headshot
	if bool(Settings.get_value("gameplay", "damage_numbers", false)):
		_on_notify("-%d" % amount, 0.6)


func _on_damaged(victim: int, attacker: int, amount: int, _zone: int, dir: Vector3, _armor: bool) -> void:
	if victim != Net.local_id:
		return
	damage_overlay.color.a = clampf(damage_overlay.color.a + amount / 120.0, 0.0, 0.55)
	var lp := Net.local_player()
	var ap: Player = Net.players.get(attacker)
	var from := Vector3.ZERO
	if ap and lp:
		from = (ap.global_position - lp.global_position)
	elif lp:
		from = -dir
	damage_indicators.append({"dir": from, "t": 1.2})
	var shake := float(Settings.get_value("accessibility", "screen_shake", 1.0))
	if lp and lp.camera and shake > 0.0 and not bool(Settings.get_value("video", "reduced_motion", false)):
		lp.recoil_offset += Vector2(randf_range(-1, 1), randf_range(0.5, 1.5)) * shake * amount * 0.03


func _on_flashed(strength: float, duration: float) -> void:
	var intensity := float(Settings.get_value("accessibility", "flash_intensity", 1.0))
	flash_strength = max(flash_strength, strength * intensity)
	flash_total = duration
	flash_time = duration
	Audio.play_2d("grenades/flash_ring.wav", linear_to_db(clampf(strength, 0.1, 1.0)) - 6.0)


func _on_notify(text: String, seconds: float) -> void:
	if text.begins_with("[Announcer]"):
		subtitle_lbl.text = text
		get_tree().create_timer(seconds).timeout.connect(func(): if subtitle_lbl.text == text: subtitle_lbl.text = "")
		return
	notify_lbl.text = text
	notify_t = seconds


func _on_spectating(target: int, free_cam: bool) -> void:
	if not Net.spectating:
		spectator_lbl.text = ""
		return
	if free_cam:
		spectator_lbl.text = "Free camera — click to follow a teammate, Space to toggle"
	else:
		var info: Dictionary = Net.infos.get(target, {"name": "?"})
		spectator_lbl.text = "Spectating %s — click for next, Space for free camera" % info.name


func _process(delta: float) -> void:
	var lp := Net.local_player()
	var m := Match
	score_lbl.text = "[color=#%s]%d[/color] : [color=#%s]%d[/color]" % [UIKit.team_color(Teams.ATTACKERS).to_html(false), m.score[Teams.ATTACKERS], UIKit.team_color(Teams.DEFENDERS).to_html(false), m.score[Teams.DEFENDERS]] if false else "%d : %d" % [m.score[Teams.ATTACKERS], m.score[Teams.DEFENDERS]]
	round_lbl.text = ("Round %d" % m.round_number) + ("  OT" if m.overtime else "") + ("  (max %d)" % m.rules.max_rounds)
	team_alive_lbl.text = "%d alive   vs   %d alive" % [m.alive_count(Teams.ATTACKERS), m.alive_count(Teams.DEFENDERS)]
	match m.state:
		m.State.WARMUP:
			state_lbl.text = "WARMUP"
			timer_lbl.text = UIKit.fmt_time(m.time_left)
		m.State.FREEZE:
			state_lbl.text = "FREEZE TIME — buy now (B)"
			timer_lbl.text = UIKit.fmt_time(m.time_left)
		m.State.LIVE:
			state_lbl.text = ""
			timer_lbl.text = UIKit.fmt_time(m.time_left)
			timer_lbl.add_theme_color_override("font_color", UIKit.BAD if m.time_left < 10.0 else UIKit.TEXT)
		m.State.PLANTED:
			state_lbl.text = "CHARGE PLANTED at %s" % m.bomb_site
			timer_lbl.text = "▮▮▮"
		m.State.ROUND_END:
			state_lbl.text = "%s win the round" % Teams.short_name(m.round_winner)
			timer_lbl.text = UIKit.fmt_time(m.time_left)
		m.State.HALFTIME:
			state_lbl.text = "HALFTIME"
			timer_lbl.text = UIKit.fmt_time(m.time_left)
		_:
			state_lbl.text = m.state_name()
			timer_lbl.text = ""
	bomb_lbl.text = ""
	if lp and lp.team == Teams.ATTACKERS:
		if m.bomb_state == "dropped":
			bomb_lbl.text = "Charge dropped!"
		elif m.bomb_carrier_id == Net.local_id and m.bomb_state == "carried":
			bomb_lbl.text = "You carry the charge (5)"
	if lp:
		health_lbl.text = str(lp.health)
		health_lbl.add_theme_color_override("font_color", UIKit.BAD if lp.health <= 25 else UIKit.TEXT)
		armor_lbl.text = str(lp.armor) + ("+H" if lp.has_helmet else "")
		money_lbl.text = "$%d" % lp.money
		var w := lp.active_weapon()
		if w and lp.alive:
			weapon_lbl.text = w.cfg.display_name + ("  [zoom %dx]" % int(w.cfg.zoom_levels[clampi(w.zoom_level, 0, w.cfg.zoom_levels.size() - 1)]) if lp.zoomed and not w.cfg.zoom_levels.is_empty() else "")
			if w.cfg.is_firearm():
				ammo_lbl.text = "%d / %d" % [w.ammo, w.reserve]
				ammo_lbl.add_theme_color_override("font_color", UIKit.BAD if w.ammo == 0 else UIKit.TEXT)
			elif w.cfg.category == "grenade":
				ammo_lbl.text = "x%d" % w.ammo
			else:
				ammo_lbl.text = ""
		else:
			weapon_lbl.text = ""
			ammo_lbl.text = ""
		_update_inventory(lp)
		var callout := m.callout_at(lp.global_position)
		callout_lbl.text = callout
		buyhint_lbl.text = ""
		if m.can_buy() and m.in_buy_zone(lp) and lp.alive and m.state != m.State.WARMUP:
			buyhint_lbl.text = "Buy zone — press B  (%s left)" % UIKit.fmt_time(m.buy_time_left)
		progress.visible = false
		progress_lbl.text = ""
		if lp.planting:
			progress.visible = true
			progress.value = lp.plant_progress * 100.0
			progress_lbl.text = "Planting..."
		elif lp.defusing:
			progress.visible = true
			progress.value = lp.defuse_progress * 100.0
			progress_lbl.text = "Defusing%s..." % (" (kit)" if lp.inventory.has_kit else "")
		elif lp.alive and lp.team == Teams.ATTACKERS and lp.inventory.has_bomb() and m.site_at(lp.global_position) != "" and m.state == m.State.LIVE:
			progress_lbl.text = "Hold E with the charge (5) selected to plant"
		elif lp.alive and lp.team == Teams.DEFENDERS and m.bomb_planted() and lp.global_position.distance_to(m.bomb_position) < 2.5:
			progress_lbl.text = "Hold E to defuse"
		low_hp_pulse += delta * 4.0
	# hit marker / damage overlay / flash
	hitmarker_t -= delta
	damage_overlay.color.a = max(damage_overlay.color.a - delta * 0.6, 0.0)
	if flash_time > 0.0:
		flash_time -= delta
		var frac := clampf(flash_time / max(flash_total, 0.01), 0.0, 1.0)
		flash_rect.color.a = clampf(flash_strength * (frac * frac * 1.6), 0.0, 1.0)
	else:
		flash_rect.color.a = max(flash_rect.color.a - delta * 2.0, 0.0)
		flash_strength = 0.0
	for d in damage_indicators:
		d.t -= delta
	damage_indicators = damage_indicators.filter(func(d): return d.t > 0.0)
	if notify_t > 0.0:
		notify_t -= delta
		if notify_t <= 0.0:
			notify_lbl.text = ""
	crosshair.visible = lp != null and lp.alive and not Net.spectating and not (Net.local_controller and Net.local_controller.ui_blocking)
	var show_player_hud := lp != null and lp.alive and not Net.spectating
	health_lbl.get_parent().visible = show_player_hud
	ammo_lbl.get_parent().visible = show_player_hud
	queue_redraw()


func _update_inventory(lp: Player) -> void:
	var want := []
	var inv := lp.inventory
	for slot in [Inventory.SLOT_PRIMARY, Inventory.SLOT_SECONDARY, Inventory.SLOT_MELEE]:
		var ws := inv.get_active(slot)
		if ws:
			want.append([slot + 1, ws.cfg.display_name, slot == lp.active_slot])
	for g in inv.slots[Inventory.SLOT_GRENADE]:
		want.append([4, "%s x%d" % [g.cfg.display_name, g.ammo], lp.active_slot == Inventory.SLOT_GRENADE and inv.get_active(4) == g])
	if inv.has_bomb():
		want.append([5, "Charge", lp.active_slot == Inventory.SLOT_BOMB])
	if inv.has_kit:
		want.append([0, "Kit", false])
	if inventory_box.get_child_count() != want.size():
		for c in inventory_box.get_children():
			c.queue_free()
		for w in want:
			inventory_box.add_child(UIKit.label("", UIKit.DIM, 13))
	var i := 0
	for c in inventory_box.get_children():
		if i < want.size():
			c.text = ("[%d] %s" % [want[i][0], want[i][1]]) if want[i][0] > 0 else want[i][1]
			c.add_theme_color_override("font_color", UIKit.ACCENT if want[i][2] else UIKit.DIM)
		i += 1


func _draw() -> void:
	var c := size / 2.0
	if hitmarker_t > 0.0:
		var col := UIKit.BAD if hitmarker_head else Color.WHITE
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 6.0, c + d * 14.0, col, 2.0)
	var lp := Net.local_player()
	if lp == null:
		return
	# directional damage indicators
	for d in damage_indicators:
		var dir: Vector3 = d.dir
		var local := lp.view_basis().inverse() * dir
		var ang := atan2(local.x, -local.z)
		var r := 90.0
		var p := c + Vector2(sin(ang), -cos(ang)) * r
		var a := clampf(d.t, 0.0, 1.0)
		var tangent := Vector2(cos(ang), sin(ang))
		var tip := c + Vector2(sin(ang), -cos(ang)) * (r + 18.0)
		draw_colored_polygon(PackedVector2Array([tip, p + tangent * 14.0, p - tangent * 14.0]), Color(1, 0.2, 0.15, a * 0.8))
	# low health vignette pulse
	if lp.alive and lp.health <= 25:
		var a := 0.12 + 0.08 * sin(low_hp_pulse)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0, 0, a), false, 40.0)
