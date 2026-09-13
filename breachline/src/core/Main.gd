extends Node
## Entry point. Handles menu flow, map loading, offline/host/join, and dedicated-server arguments:
##   --server            run as dedicated server (use with --headless)
##   --port N            listen port (default 27015)
##   --map NAME          map to load (default foundry)
##   --bots N            bots to add on a dedicated server
##   --autostart         start the match immediately (dedicated servers do this by default)
##   --connect IP:PORT   connect directly as a client
##   --smoke-test N      load the map with bots, run N seconds, print a report and quit
##   --fast              short warmup/freeze/round timers (testing)
##   --screenshot PATH   save a screenshot of the viewport just before the smoke test ends
##   --bot-difficulty N  0..3
##   --open lobby|buy    (testing) open the offline lobby, or the buy menu during a smoke test
##   --spectate          (testing) host joins spectators so 5v5 bots play
##   --net-sim L,P,J     (testing) simulate inbound latency L ms, loss P (0-1), jitter J ms
##   --screenshot-delay S (testing) take --screenshot after S seconds in any mode, then quit

const DEFAULT_MAP := "foundry"

var ui_layer: CanvasLayer
var world_root: Node3D
var world: MapLoader
var current_menu: Control
var menu_stack: Array = []
var hud: Control
var buy_menu: Control
var scoreboard: Control
var pause_menu: Control
var round_end: Control
var results: Control
var in_match := false
var smoke_test_time := 0.0
var smoke_test := false
var headless := false
var screenshot_path := ""
var spectate_host := false
var screenshot_delay := -1.0
var open_target := ""


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	Events.open_menu.connect(_on_open_menu)
	Events.match_state_changed.connect(_on_match_state)
	Events.local_player_ready.connect(func(_p): _ensure_hud())
	var args := OS.get_cmdline_user_args()
	var opts := _parse_args(args)
	if opts.has("fast"):
		Match.lock_rules = true
		Match.rules.warmup_time = 2.0
		Match.rules.freeze_time = 3.0
		Match.rules.round_time = float(opts.get("round-time", "40"))
		Match.rules.round_end_time = 3.0
		Match.rules.halftime_time = 3.0
	spectate_host = opts.has("spectate")
	if opts.has("net-sim"):
		var parts := str(opts["net-sim"]).split(",")
		Net.set_network_sim(int(parts[0]), float(parts[1]) if parts.size() > 1 else 0.0, int(parts[2]) if parts.size() > 2 else 0)
	if opts.has("bot-difficulty"):
		Settings.data["gameplay"]["bot_difficulty"] = int(opts["bot-difficulty"])
	screenshot_path = str(opts.get("screenshot", ""))
	open_target = str(opts.get("open", ""))
	if opts.has("screenshot-delay"):
		screenshot_delay = float(opts["screenshot-delay"])
	if opts.has("server"):
		_start_dedicated(opts)
	elif opts.has("connect"):
		var parts := str(opts.connect).split(":")
		if opts.has("smoke-test"):
			smoke_test = true
			smoke_test_time = float(opts.get("smoke-test", "20"))
		_start_join(parts[0], int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT)
		if headless:
			# headless test client: auto-ready and join a team once the lobby arrives
			Events.lobby_updated.connect(_headless_client_autoready)
	elif opts.has("smoke-test"):
		smoke_test = true
		smoke_test_time = float(opts.get("smoke-test", "20"))
		_start_offline(true)
	elif open_target == "lobby":
		_start_offline(false)
	else:
		_show_menu("main")


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if "=" in key:
				var kv := key.split("=", true, 1)
				out[kv[0]] = kv[1]
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[key] = args[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out


# ------------------------------------------------------------------------------ flows
func _start_offline(autostart: bool) -> void:
	var pname := str(Settings.get_value("player", "name", "Operator"))
	if not Net.host(int(Settings.get_value("network", "port", Net.DEFAULT_PORT)), true, pname):
		# port busy (e.g. a second local instance): try a random port so offline play still works
		Net.host(randi_range(30000, 40000), true, pname)
	_load_map(DEFAULT_MAP)
	var per_team := int(Settings.get_value("gameplay", "bots_per_team", 4))
	var diff := int(Settings.get_value("gameplay", "bot_difficulty", 1))
	if spectate_host:
		Net.server_set_team(Net.local_id, Teams.SPECTATOR)
		per_team = 5
	for team in [Teams.ATTACKERS, Teams.DEFENDERS]:
		var want: int = per_team if Net.infos[Net.local_id].team != team else per_team
		while Match.team_count(team) < min(want + (0 if Net.infos[Net.local_id].team != team else 1), Match.rules.team_size):
			Net.server_add_bot(team, diff)
	if autostart:
		Match.server_start_match()
		_ensure_hud()
	else:
		_show_menu("lobby")


func _start_host() -> void:
	var pname := str(Settings.get_value("player", "name", "Operator"))
	if not Net.host(int(Settings.get_value("network", "port", Net.DEFAULT_PORT)), true, pname):
		_show_menu("main")
		return
	_load_map(DEFAULT_MAP)
	_show_menu("lobby")


func _start_join(ip: String, port: int) -> void:
	var pname := str(Settings.get_value("player", "name", "Operator"))
	Net.join(ip, port, pname)
	_show_menu("lobby")


func _start_dedicated(opts: Dictionary) -> void:
	var port := int(opts.get("port", Net.DEFAULT_PORT))
	Net.server_name = str(opts.get("name", "Breachline Dedicated"))
	if not Net.host(port, false, "server"):
		push_error("dedicated server could not bind port %d" % port)
		get_tree().quit(1)
		return
	_load_map(str(opts.get("map", DEFAULT_MAP)))
	var bots := int(opts.get("bots", 0))
	for i in bots:
		Net.server_add_bot()
	print("[server] Breachline dedicated server on port %d, map %s, %d bots. Waiting for players (match starts when all humans are ready; --autostart starts now)." % [port, opts.get("map", DEFAULT_MAP), bots])
	if opts.has("autostart"):
		Match.server_start_match()
	var lc := load("res://src/ui/Lobby.gd") if false else null


func _load_map(mname: String) -> bool:
	_unload_map()
	world = MapLoader.new()
	world_root.add_child(world)
	if not world.build(mname):
		world.queue_free()
		world = null
		return false
	Net.set_world(world, mname)
	_validate_spawns_later(world, mname)
	if not headless:
		Audio.start_ambience(["ambient/foundry_hum.wav", "ambient/wind.wav", "ambient/metal_clanks.wav"])
	return true


func _validate_spawns_later(w: MapLoader, mname: String) -> void:
	# the navigation map syncs on a later physics step; wait for its first iteration
	var map_rid := w.get_world_3d().navigation_map
	var waited := 0
	while NavigationServer3D.map_get_iteration_id(map_rid) == 0 and waited < 120:
		await get_tree().physics_frame
		waited += 1
	if not is_instance_valid(w):
		return
	var problems := w.validate_spawns()
	if problems.size() > 0:
		for p in problems:
			push_warning("spawn validation: " + p)
	else:
		print("[map] %s loaded, spawn validation OK" % mname)


func _unload_map() -> void:
	if world:
		world.queue_free()
		world = null
	Audio.stop_ambience()
	_clear_hud()


func _leave() -> void:
	Net.shutdown()
	Match.state = Match.State.LOBBY
	_unload_map()
	menu_stack.clear()
	_show_menu("main")


# ------------------------------------------------------------------------------ menus
func _show_menu(name: String) -> void:
	if headless:
		return
	if current_menu:
		current_menu.queue_free()
		current_menu = null
	var script_path := {"main": "res://src/ui/MainMenu.gd", "lobby": "res://src/ui/Lobby.gd", "settings": "res://src/ui/SettingsMenu.gd"}.get(name, "")
	if script_path.is_empty():
		return
	current_menu = load(script_path).new()
	current_menu.name = "Menu_" + name
	ui_layer.add_child(current_menu)
	if Net.local_controller:
		Net.local_controller.set_ui_blocking(true)
	if name == "main":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif name == "lobby":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menu() -> void:
	if current_menu:
		current_menu.queue_free()
		current_menu = null
	if Net.local_controller and in_match:
		Net.local_controller.set_ui_blocking(false)


func _on_open_menu(name: String) -> void:
	match name:
		"main":
			_show_menu("main")
		"settings":
			menu_stack.append("lobby" if Net.active() and not in_match else ("pause" if in_match else "main"))
			_show_menu("settings")
		"back":
			var prev: String = menu_stack.pop_back() if not menu_stack.is_empty() else "main"
			if prev == "pause":
				_close_menu()
				_toggle_pause(true)
			else:
				_show_menu(prev)
		"play_offline":
			_start_offline(false)
		"host":
			_start_host()
		"leave":
			_leave()
		"close_pause":
			_toggle_pause(false)
		"close_buy":
			_toggle_buy(false)
		"reload_map":
			var mname := Net.map_name
			var was_running := Match.state != Match.State.LOBBY
			_load_map(mname)
			for p: Player in Net.players.values():
				world.add_child(p) if p.get_parent() == null else p.reparent(world)
			if was_running and Net.is_server():
				Match.server_start_match()
		_:
			if name.begins_with("join:"):
				var parts := name.split(":")
				_start_join(parts[1], int(parts[2]))
			elif name.begins_with("load_map:"):
				_load_map(name.substr(9))
				for p: Player in Net.players.values():
					if p.get_parent() != world:
						p.reparent(world)
				_show_menu("lobby")


func _on_match_state(state: int, _t: float) -> void:
	var m := Match
	var was_in_match := in_match
	in_match = state not in [m.State.LOBBY, m.State.MATCH_END]
	if in_match and not was_in_match:
		_close_menu()
		_ensure_hud()
		if results:
			results.queue_free()
			results = null
	if state == m.State.LOBBY and was_in_match:
		_clear_hud()
		_show_menu("lobby")
	if state == m.State.MATCH_END and not headless and results == null:
		_toggle_buy(false)
		results = load("res://src/ui/MatchResultsScreen.gd").new()
		ui_layer.add_child(results)
		if Net.local_controller:
			Net.local_controller.set_ui_blocking(true)
	if state != m.State.MATCH_END and results:
		results.queue_free()
		results = null


func _ensure_hud() -> void:
	if headless or hud != null or not in_match:
		return
	hud = load("res://src/ui/HUD.gd").new()
	ui_layer.add_child(hud)
	scoreboard = load("res://src/ui/Scoreboard.gd").new()
	scoreboard.visible = false
	ui_layer.add_child(scoreboard)
	round_end = load("res://src/ui/RoundEndScreen.gd").new()
	ui_layer.add_child(round_end)
	if Net.local_controller:
		Net.local_controller.set_ui_blocking(false)


func _clear_hud() -> void:
	for n in [hud, scoreboard, round_end, buy_menu, pause_menu, results]:
		if n and is_instance_valid(n):
			n.queue_free()
	hud = null
	scoreboard = null
	round_end = null
	buy_menu = null
	pause_menu = null
	results = null


func _toggle_buy(open: bool) -> void:
	if headless:
		return
	if open and buy_menu == null:
		buy_menu = load("res://src/ui/BuyMenu.gd").new()
		ui_layer.add_child(buy_menu)
		Net.local_controller.set_ui_blocking(true)
	elif not open and buy_menu:
		buy_menu.queue_free()
		buy_menu = null
		if pause_menu == null and current_menu == null:
			Net.local_controller.set_ui_blocking(false)


func _toggle_pause(open: bool) -> void:
	if headless:
		return
	if open and pause_menu == null:
		pause_menu = load("res://src/ui/PauseMenu.gd").new()
		ui_layer.add_child(pause_menu)
		Net.local_controller.set_ui_blocking(true)
	elif not open and pause_menu:
		pause_menu.queue_free()
		pause_menu = null
		if buy_menu == null and current_menu == null and results == null:
			Net.local_controller.set_ui_blocking(false)


func _unhandled_input(event: InputEvent) -> void:
	if not in_match or headless or Net.local_controller == null:
		return
	if DebugConsole.visible_console:
		return
	if event.is_action_pressed("pause"):
		if buy_menu:
			_toggle_buy(false)
		elif current_menu:
			_close_menu()
			_toggle_pause(true)
		else:
			_toggle_pause(pause_menu == null)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("buy_menu") and pause_menu == null and current_menu == null:
		_toggle_buy(buy_menu == null)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scoreboard") and scoreboard:
		scoreboard.visible = true
	elif event.is_action_released("scoreboard") and scoreboard:
		scoreboard.visible = false


func _process(delta: float) -> void:
	if screenshot_delay >= 0.0:
		screenshot_delay -= delta
		if screenshot_delay < 0.0:
			screenshot_delay = -1.0
			_finish_smoke_test()
	if smoke_test:
		smoke_test_time -= delta
		_smoke_log_timer -= delta
		if _smoke_log_timer <= 0.0:
			_smoke_log_timer = 10.0
			_smoke_periodic()
		if open_target == "buy" and in_match and buy_menu == null and smoke_test_time < 6.0:
			_toggle_buy(true)
		if smoke_test_time <= 0.0:
			smoke_test = false
			_finish_smoke_test()


func _finish_smoke_test() -> void:
	if screenshot_path != "" and not headless:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(screenshot_path)
		print("[smoke] screenshot saved to " + screenshot_path)
	_smoke_report()
	get_tree().quit()


var _autoreadied := false
var _smoke_log_timer := 5.0


func _smoke_periodic() -> void:
	if not Net.is_server():
		return
	var lines := []
	for p: Player in Net.players.values():
		var brain: Node = p.get_node_or_null("Brain")
		if brain:
			var extra := ""
			if OS.has_environment("BOT_NAV_DEBUG"):
				var nav: NavigationAgent3D = brain.nav
				var map_rid := p.get_world_3d().navigation_map
				var closest := NavigationServer3D.map_get_closest_point(map_rid, p.global_position)
				extra = " nav[fin=%s dist=%.1f next=%s tgt=%s off=%.2f path=%d vel=%.1f floor=%s]" % [nav.is_navigation_finished(), nav.distance_to_target(), nav.get_next_path_position().round(), nav.target_position.round(), closest.distance_to(p.global_position), nav.get_current_navigation_path().size(), p.horizontal_speed(), p.is_on_floor()]
			lines.append("%s:%s%s@%s%s" % [p.player_name.replace("[BOT] ", ""), brain.state_name() if p.alive else "DEAD", "*" if p.inventory.has_bomb() else "", p.global_position.round(), extra])
	print("[smoke %ds] %s round %d bomb %s | %s" % [int(smoke_test_time), Match.state_name(), Match.round_number, Match.bomb_state, " ".join(lines)])


func _headless_client_autoready() -> void:
	if _autoreadied or not Net.is_client() or not Net.infos.has(Net.local_id):
		return
	_autoreadied = true
	Net.rpc_id(1, "rpc_ready", true)


func _smoke_report() -> void:
	print("=== smoke test report ===")
	if hud:
		print("hud rect: %s" % hud.get_global_rect())
	print("net mode %d local id %d ping %d ms snapshots up to tick %d, infos %d" % [Net.mode, Net.local_id, Net.ping_ms, Net.last_snapshot_tick, Net.infos.size()])
	print("match state: %s round %d score %d:%d bomb %s" % [Match.state_name(), Match.round_number, Match.score[Teams.ATTACKERS], Match.score[Teams.DEFENDERS], Match.bomb_state])
	for p: Player in Net.players.values():
		var brain: Node = p.get_node_or_null("Brain")
		print("  %-16s team %d hp %3d money %5d k/d %d/%d pos %s %s" % [p.player_name, p.team, p.health, p.money, p.stats.kills, p.stats.deaths, p.global_position.round(), brain.state_name() if brain else ""])
	print("entities: %d, server tick %d, weapon load errors: %d" % [Net.entities.size(), Net.server_tick, WeaponDB.load_errors.size()])
