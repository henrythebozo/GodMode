extends CanvasLayer
## Autoload: in-game developer console (toggle with `). Commands run on the server; a listen-server
## host may run them remotely, dedicated servers only accept commands from their own stdin/console.

var panel: PanelContainer
var log_label: RichTextLabel
var input: LineEdit
var visible_console := false
var history: Array = []
var history_idx := -1
var god_players: Dictionary = {}

const COMMANDS := {
	"help": "list commands",
	"restart_round": "restart the current round",
	"start": "start the match from the lobby",
	"end_round <attackers|defenders>": "force a round winner",
	"money <amount> [all]": "set your (or everyone's) money",
	"bot_add [attackers|defenders] [0-3]": "add a bot (optional team and difficulty)",
	"bot_kick": "remove all bots",
	"bot_difficulty <0-3>": "set difficulty for all bots",
	"noclip": "toggle noclip flight for your player",
	"god": "toggle invulnerability",
	"give <weapon_id>": "give yourself a weapon",
	"kill": "kill your own player",
	"map_reload": "reload the current map and restart",
	"net_sim <latency_ms> <loss 0-1> [jitter_ms]": "simulate network conditions",
	"timescale <x>": "engine time scale",
	"plant": "teleport to site A with the bomb equipped",
	"tp <A|B|mid>": "teleport to a site or the yard",
	"state": "print match & net state",
	"validate_spawns": "run spawn validation",
	"fps": "toggle fps counter",
	"quit": "exit the game",
}


func _ready() -> void:
	layer = 100
	if DisplayServer.get_name() == "headless":
		return
	panel = PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.45
	panel.visible = false
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.bbcode_enabled = true
	vb.add_child(log_label)
	input = LineEdit.new()
	input.placeholder_text = "type 'help'"
	input.text_submitted.connect(_on_submit)
	vb.add_child(input)
	add_child(panel)
	log_line("[color=gray]Breachline console. Type help.[/color]")


func _input(event: InputEvent) -> void:
	if panel == null:
		return
	if event.is_action_pressed("console"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible_console and event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP and not history.is_empty():
			history_idx = clampi(history_idx - 1, 0, history.size() - 1)
			input.text = history[history_idx]
			input.caret_column = input.text.length()
		elif event.keycode == KEY_DOWN and not history.is_empty():
			history_idx = clampi(history_idx + 1, 0, history.size())
			input.text = history[history_idx] if history_idx < history.size() else ""


func toggle() -> void:
	visible_console = not visible_console
	panel.visible = visible_console
	if visible_console:
		input.grab_focus()
		input.text = ""
	if Net.local_controller:
		Net.local_controller.set_ui_blocking(visible_console)


func log_line(text: String) -> void:
	if log_label:
		log_label.append_text(text + "\n")
	print("[console] " + text)


func _on_submit(text: String) -> void:
	input.text = ""
	if text.strip_edges().is_empty():
		return
	history.append(text)
	history_idx = history.size()
	log_line("> " + text)
	if Net.is_client():
		Net.rpc_id(1, "rpc_console", text)
		log_line("[color=gray](sent to server; only the host is allowed)[/color]")
	else:
		execute(text)


func execute(line: String) -> void:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	var lp := Net.local_player()
	match cmd:
		"help":
			for k in COMMANDS:
				log_line("[b]%s[/b] - %s" % [k, COMMANDS[k]])
		"restart_round":
			if Match.state == Match.State.LOBBY:
				log_line("no match running")
			else:
				Match._start_round()
				log_line("round restarted")
		"start":
			Match.server_start_match()
		"end_round":
			var t := Teams.ATTACKERS if args.size() > 0 and args[0].begins_with("a") else Teams.DEFENDERS
			Match._end_round(t, Economy.REASON_ELIMINATION)
		"money":
			var amount := int(args[0]) if args.size() > 0 else 16000
			var targets := Net.players.values() if args.size() > 1 and args[1] == "all" else ([lp] if lp else [])
			for p in targets:
				p.money = clampi(amount, 0, Match.economy_cfg.max_money)
				Net.server_sync_inventory(p)
			log_line("money set")
		"bot_add":
			var team := Teams.NONE
			if args.size() > 0:
				team = Teams.ATTACKERS if args[0].begins_with("a") else Teams.DEFENDERS
			var diff := int(args[1]) if args.size() > 1 else -1
			var b := Net.server_add_bot(team, diff)
			if b:
				log_line("added %s to %s" % [b.player_name, Teams.short_name(b.team)])
		"bot_kick":
			Net.server_remove_bots()
			log_line("bots removed")
		"bot_difficulty":
			var d := int(args[0]) if args.size() > 0 else 1
			for p: Player in Net.players.values():
				var brain: Node = p.get_node_or_null("Brain")
				if brain:
					brain.set_difficulty(d)
			Settings.set_value("gameplay", "bot_difficulty", d)
			log_line("bot difficulty %d" % d)
		"noclip":
			if lp:
				lp.noclip = not lp.noclip
				lp.collision_layer = 0 if lp.noclip else 2
				log_line("noclip %s" % ("on" if lp.noclip else "off"))
		"god":
			if lp:
				god_players[lp.peer_id] = not god_players.get(lp.peer_id, false)
				if god_players[lp.peer_id]:
					if not lp.damaged.is_connected(_god_heal):
						lp.damaged.connect(_god_heal.bind(lp))
				log_line("god %s" % ("on" if god_players[lp.peer_id] else "off"))
		"give":
			if lp and args.size() > 0:
				var cfg := WeaponDB.get_config(args[0])
				if cfg == null:
					log_line("unknown weapon; ids: " + ", ".join(WeaponDB.weapons.keys()))
				else:
					if cfg.slot == "primary" and lp.inventory.has_slot(0):
						lp.inventory.remove(0)
					if cfg.slot == "secondary" and lp.inventory.has_slot(1):
						lp.inventory.remove(1)
					lp.inventory.give(cfg)
					Net.server_sync_inventory(lp)
					log_line("gave " + cfg.display_name)
		"kill":
			if lp and lp.alive:
				lp.server_die(0, "console", false)
		"map_reload":
			Events.open_menu.emit("reload_map")
			log_line("reloading map")
		"net_sim":
			var lat := int(args[0]) if args.size() > 0 else 0
			var loss := float(args[1]) if args.size() > 1 else 0.0
			var jit := int(args[2]) if args.size() > 2 else 0
			Net.set_network_sim(lat, loss, jit)
			log_line("net sim: %dms latency, %.0f%% loss, %dms jitter" % [lat, loss * 100.0, jit])
		"timescale":
			Engine.time_scale = clampf(float(args[0]) if args.size() > 0 else 1.0, 0.05, 5.0)
			log_line("timescale %.2f" % Engine.time_scale)
		"plant":
			if lp:
				lp.inventory.give(WeaponDB.get_config("bomb"))
				lp.switch_to_slot(Inventory.SLOT_BOMB)
				_tp(lp, "A")
				Net.server_sync_inventory(lp)
		"tp":
			if lp:
				_tp(lp, args[0] if args.size() > 0 else "mid")
		"state":
			log_line("match: %s round %d score %d-%d bomb %s | net: mode %d players %d entities %d tick %d" % [Match.state_name(), Match.round_number, Match.score[Teams.ATTACKERS], Match.score[Teams.DEFENDERS], Match.bomb_state, Net.mode, Net.players.size(), Net.entities.size(), Net.server_tick])
			for p: Player in Net.players.values():
				var brain: Node = p.get_node_or_null("Brain")
				log_line("  %s team %d hp %d money %d %s %s" % [p.player_name, p.team, p.health, p.money, "alive" if p.alive else "dead", brain.state_name() if brain else ""])
		"validate_spawns":
			var w := Net.world
			if w and w.has_method("validate_spawns"):
				var problems: PackedStringArray = w.validate_spawns()
				log_line("spawn validation: %s" % ("OK" if problems.is_empty() else "\n".join(problems)))
		"fps":
			Events.notification.emit("FPS: %d" % Engine.get_frames_per_second(), 2.0)
		"quit":
			get_tree().quit()
		_:
			log_line("unknown command: " + cmd)


func _god_heal(_amount: int, _attacker: int, _zone: int, p: Player) -> void:
	if god_players.get(p.peer_id, false):
		p.health = Match.rules.max_health


func _tp(p: Player, where: String) -> void:
	var pos := p.global_position
	var sites: Dictionary = Match.layout.get("sites", {})
	if where.to_upper() in sites:
		var s: Dictionary = sites[where.to_upper()]
		pos = Vector3(s.pos[0], s.pos[1] + 0.2, s.pos[2])
	else:
		var size: Array = Match.layout.get("size", [120, 100])
		pos = Vector3(size[0] * 0.5, 0.2, size[1] * 0.5)
	p.global_position = pos
	p.velocity = Vector3.ZERO
	log_line("teleported to " + where)
