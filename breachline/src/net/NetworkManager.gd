extends Node
## Autoload "Net": server-authoritative networking hub.
##  * Server: owns every Player node, consumes InputCmds, resolves shots with lag compensation,
##    spawns entities, broadcasts snapshots and reliable events.
##  * Client: sends InputCmds, predicts the local player, interpolates remote players, mirrors entities.
## See docs/MULTIPLAYER.md for what is production-ready vs. prototype.

enum Mode { NONE, SERVER, CLIENT }

const DEFAULT_PORT := 27015
const SNAPSHOT_EVERY_TICKS := 2
const PREDICTION_TOLERANCE := 0.06
const RECONNECT_GRACE := 60.0
const INTERP_DELAY_TICKS := 2

var mode: int = Mode.NONE
var listen_server := false
var peer: ENetMultiplayerPeer
var players: Dictionary = {}          # id -> Player (server: all; client: all)
var infos: Dictionary = {}            # id -> lobby info {name, team, ready, bot, ping, token, connected}
var local_id: int = 0
var server_tick: int = 0
var client_tick: int = 0
var world: Node3D
var map_name := ""
var input_queue: Dictionary = {}      # id -> Array[InputCmd]
var last_cmds: Dictionary = {}
var lagcomp := LagCompensation.new()
var local_controller: Node
var spectator: Node
var spectating := false
var history: Array = []               # client prediction history
var last_ack_tick := 0
var last_snapshot_tick := 0
var ping_ms := 0
var _ping_timer := 0.0
var _ping_sent := 0.0
var next_bot_id := -1
var entities: Dictionary = {}         # id -> Node
var next_entity_id := 1
var session_token := ""
var connect_target := ""
var reconnect_attempts := 0
var _reconnect_timer := 0.0
var sim_latency_ms := 0
var sim_loss := 0.0
var sim_jitter_ms := 0
var _inbound: Array = []              # simulated-latency queue of [deliver_time, Callable]
var remote_buffers: Dictionary = {}   # id -> Array of snapshot states (client interpolation)
var browser: ServerBrowser
var server_name := "Breachline Server"
var listen_port := DEFAULT_PORT
var pending_disconnect: Dictionary = {}   # id -> disconnect time (reconnect grace)
var local_player_name := "Operator"
var unreliable_seq := 0


func _ready() -> void:
	session_token = str(randi()) + str(Time.get_ticks_usec())
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	browser = ServerBrowser.new()
	add_child(browser)
	_load_sim_settings()
	Events.settings_changed.connect(_load_sim_settings)


func _load_sim_settings() -> void:
	sim_latency_ms = int(Settings.get_value("network", "sim_latency_ms", 0))
	sim_loss = float(Settings.get_value("network", "sim_loss", 0.0))
	sim_jitter_ms = int(Settings.get_value("network", "sim_jitter_ms", 0))


func is_server() -> bool:
	return mode == Mode.SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT


func active() -> bool:
	return mode != Mode.NONE


func local_player() -> Player:
	return players.get(local_id)


func server_info() -> Dictionary:
	return {"name": server_name, "map": map_name, "players": _human_count(), "bots": _bot_count(), "max": Match.rules.max_players, "port": listen_port, "state": Match.state_name()}


## Peer ids of connected human clients (excluding the local listen-server host).
func remote_human_peers() -> Array:
	var out := []
	var peers := multiplayer.get_peers()
	for id in infos.keys():
		if not infos[id].bot and infos[id].connected and id != local_id and id in peers:
			out.append(id)
	return out


func _human_count() -> int:
	var n := 0
	for i in infos.values():
		if not i.bot and i.connected:
			n += 1
	return n


func _bot_count() -> int:
	var n := 0
	for i in infos.values():
		if i.bot:
			n += 1
	return n


# ============================================================================= lifecycle
func host(port: int, listen: bool, pname: String) -> bool:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 32)
	if err != OK:
		Events.connection_state_changed.emit("error", "Could not bind port %d" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	listen_port = port
	listen_server = listen
	local_id = 1
	local_player_name = pname
	server_tick = 0
	browser.start_server_beacon()
	if listen:
		_server_register_player(1, pname, session_token, false)
	Events.connection_state_changed.emit("hosting", "Listening on port %d" % port)
	return true


func join(ip: String, port: int, pname: String) -> bool:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		Events.connection_state_changed.emit("error", "Could not create client")
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	local_player_name = pname
	connect_target = "%s:%d" % [ip, port]
	Events.connection_state_changed.emit("connecting", connect_target)
	return true


func shutdown() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	mode = Mode.NONE
	listen_server = false
	for p in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	infos.clear()
	for e in entities.values():
		if is_instance_valid(e):
			e.queue_free()
	entities.clear()
	input_queue.clear()
	last_cmds.clear()
	history.clear()
	remote_buffers.clear()
	pending_disconnect.clear()
	_inbound.clear()
	browser.stop()
	spectating = false
	local_id = 0
	reconnect_attempts = 0
	Events.lobby_updated.emit()


func set_world(w: Node3D, mname: String) -> void:
	world = w
	map_name = mname


# ============================================================================= peers
func _on_peer_connected(id: int) -> void:
	if is_server():
		print("[net] peer connected: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	print("[net] peer disconnected: %d" % id)
	if infos.has(id):
		infos[id].connected = false
		pending_disconnect[id] = Time.get_ticks_msec() / 1000.0
		var p: Player = players.get(id)
		if p:
			p.disconnected = true
		Events.notification.emit("%s lost connection" % infos[id].name, 4.0)
		_broadcast_lobby()


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	reconnect_attempts = 0
	Events.connection_state_changed.emit("connected", "Handshaking")
	rpc_id(1, "rpc_hello", local_player_name, session_token)


func _on_connection_failed() -> void:
	Events.connection_state_changed.emit("error", "Connection failed")
	_try_reconnect()


func _on_server_disconnected() -> void:
	Events.connection_state_changed.emit("disconnected", "Server closed the connection")
	_try_reconnect()


func _try_reconnect() -> void:
	if connect_target.is_empty() or reconnect_attempts >= 5:
		shutdown()
		Events.open_menu.emit("main")
		return
	reconnect_attempts += 1
	_reconnect_timer = 2.0 * reconnect_attempts
	Events.connection_state_changed.emit("reconnecting", "Attempt %d" % reconnect_attempts)


# ============================================================================= RPC: client -> server
@rpc("any_peer", "call_remote", "reliable")
func rpc_hello(pname: String, token: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = NetValidation.sanitize_name(pname)
	# reconnect: same token as a disconnected player -> reattach
	for old_id in infos.keys():
		if infos[old_id].token == token and not infos[old_id].connected and not infos[old_id].bot:
			_server_reattach(old_id, id)
			return
	if _human_count() >= Match.rules.max_players:
		rpc_id(id, "rpc_kicked", "Server full")
		return
	_server_register_player(id, pname, token, false)


func _server_reattach(old_id: int, new_id: int) -> void:
	var info: Dictionary = infos[old_id]
	infos.erase(old_id)
	pending_disconnect.erase(old_id)
	info.connected = true
	infos[new_id] = info
	var p: Player = players.get(old_id)
	if p:
		players.erase(old_id)
		p.peer_id = new_id
		p.name = "Player_%d" % new_id
		p.disconnected = false
		players[new_id] = p
		lagcomp.forget(old_id)
		if input_queue.has(old_id):
			input_queue.erase(old_id)
	Events.notification.emit("%s reconnected" % info.name, 4.0)
	_server_send_welcome(new_id)
	for pid in remote_human_peers():
		rpc_id(pid, "rpc_reid_player", old_id, new_id)
	_broadcast_lobby()


func _server_register_player(id: int, pname: String, token: String, bot: bool) -> void:
	var team: int = Match.pick_team_for_new_player()
	infos[id] = {"name": pname, "team": team, "ready": bot, "bot": bot, "ping": 0, "token": token, "connected": true, "difficulty": int(Settings.get_value("gameplay", "bot_difficulty", 1))}
	var p := _spawn_player_node(id, pname, team, bot)
	p.money = Match.economy_cfg.start_money
	p.full_reset_inventory()
	if not bot and id != 1:
		_server_send_welcome(id)
	elif id == 1 and listen_server:
		_setup_local_player(p)
	for pid in remote_human_peers():
		if pid != id:
			rpc_id(pid, "rpc_spawn_player", id, _player_spawn_dict(p))
	Events.player_joined.emit(id, pname, team)
	_broadcast_lobby()
	if Match.state != Match.State.LOBBY and Match.state != Match.State.MATCH_END:
		Match.server_late_join(p)


func _server_send_welcome(id: int) -> void:
	rpc_id(id, "rpc_welcome", id, map_name, _lobby_dict(), Match.rules_dict())
	for pid in players.keys():
		rpc_id(id, "rpc_spawn_player", pid, _player_spawn_dict(players[pid]))
	for eid in entities.keys():
		rpc_id(id, "rpc_entity", eid, "spawn", _entity_spawn_dict(entities[eid]))
	rpc_id(id, "rpc_match_state", Match.state_dict())
	rpc_id(id, "rpc_inventory", players[id].inventory.serialize(), players[id].money, players[id].armor, players[id].has_helmet)


func _player_spawn_dict(p: Player) -> Dictionary:
	return {"name": p.player_name, "team": p.team, "bot": p.is_bot, "p": p.global_position, "yaw": p.yaw, "alive": p.alive, "stats": p.stats.duplicate(), "money": p.money}


func _lobby_dict() -> Dictionary:
	var d := {}
	for id in infos:
		var i: Dictionary = infos[id]
		var p: Player = players.get(id)
		d[id] = {"name": i.name, "team": i.team, "ready": i.ready, "bot": i.bot, "ping": i.ping, "connected": i.connected,
			"stats": p.stats.duplicate() if p else {}, "alive": p.alive if p else false, "money": p.money if p else 0}
	return d


func _broadcast_lobby() -> void:
	var d := _lobby_dict()
	for id in remote_human_peers():
		rpc_id(id, "rpc_lobby", d)
	_apply_lobby(d)


@rpc("any_peer", "call_remote", "reliable")
func rpc_set_team(team: int) -> void:
	if not is_server():
		return
	server_set_team(multiplayer.get_remote_sender_id(), team)


func server_set_team(id: int, team: int) -> void:
	if not infos.has(id) or team not in [Teams.ATTACKERS, Teams.DEFENDERS, Teams.SPECTATOR]:
		return
	if team != Teams.SPECTATOR and Match.team_count(team) >= Match.rules.team_size and not infos[id].bot:
		rpc_id(id, "rpc_event", "notify", {"text": "That team is full", "seconds": 3.0}) if id != local_id else Events.notification.emit("That team is full", 3.0)
		return
	infos[id].team = team
	var p: Player = players.get(id)
	if p:
		var was_alive := p.alive
		p.team = team
		if was_alive:
			p.server_die(0, "", false)
		if p.model:
			p.model.queue_free()
			p.model = null
			p.setup_visuals(id == local_id)
		for pid in remote_human_peers():
			rpc_id(pid, "rpc_player_team", id, team)
	Events.player_team_changed.emit(id, team)
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func rpc_ready(r: bool) -> void:
	if not is_server():
		return
	server_set_ready(multiplayer.get_remote_sender_id(), r)


func server_set_ready(id: int, r: bool) -> void:
	if infos.has(id):
		infos[id].ready = r
		_broadcast_lobby()
		Match.server_check_ready()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_input(bytes: PackedByteArray) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_simulated_delivery(func(): _server_receive_input(id, bytes))


func _server_receive_input(id: int, bytes: PackedByteArray) -> void:
	if not players.has(id):
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var count := buf.get_u8()
	var q: Array = input_queue.get(id, [])
	var last_tick: int = last_cmds[id].tick if last_cmds.has(id) else -1
	for i in count:
		var cmd := InputCmd.unpack(buf)
		if not NetValidation.sanitize_cmd(cmd, server_tick):
			continue
		if cmd.tick <= last_tick or (not q.is_empty() and cmd.tick <= q[-1].tick):
			continue
		q.append(cmd)
	while q.size() > 32:
		q.pop_front()
	input_queue[id] = q


@rpc("any_peer", "call_remote", "reliable")
func rpc_buy(weapon_id: String) -> void:
	if is_server():
		Match.server_buy(multiplayer.get_remote_sender_id(), weapon_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_refund(weapon_id: String) -> void:
	if is_server():
		Match.server_refund(multiplayer.get_remote_sender_id(), weapon_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_chat(text: String, team_only: bool) -> void:
	if is_server():
		server_chat(multiplayer.get_remote_sender_id(), text, team_only)


func server_chat(id: int, text: String, team_only: bool) -> void:
	text = NetValidation.sanitize_chat(text)
	if text.is_empty():
		return
	var sender_team: int = infos[id].team if infos.has(id) else Teams.NONE
	for pid in infos.keys():
		if infos[pid].bot or not infos[pid].connected:
			continue
		if team_only and infos[pid].team != sender_team:
			continue
		if pid == local_id:
			Events.chat_message.emit(id, team_only, text)
		elif pid in remote_human_peers():
			rpc_id(pid, "rpc_event", "chat", {"sender": id, "team": team_only, "text": text})


@rpc("any_peer", "call_remote", "unreliable")
func rpc_ping(t: float) -> void:
	if is_server():
		rpc_id(multiplayer.get_remote_sender_id(), "rpc_pong", t)


@rpc("any_peer", "call_remote", "reliable")
func rpc_vote_surrender(yes: bool) -> void:
	if is_server():
		Match.server_vote_surrender(multiplayer.get_remote_sender_id(), yes)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_rematch() -> void:
	if is_server():
		Match.server_request_rematch(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func rpc_console(cmd: String) -> void:
	# Only the listen-server host may run console commands remotely; dedicated servers ignore clients.
	if is_server() and multiplayer.get_remote_sender_id() == 1:
		DebugConsole.execute(cmd)


@rpc("any_peer", "call_remote", "reliable")
func rpc_report_ping(ms: int) -> void:
	if is_server():
		var id := multiplayer.get_remote_sender_id()
		if infos.has(id):
			infos[id].ping = ms


# ============================================================================= RPC: server -> client
@rpc("authority", "call_remote", "reliable")
func rpc_welcome(id: int, mname: String, lobby: Dictionary, rules: Dictionary) -> void:
	local_id = id
	Match.apply_rules_dict(rules)
	Events.connection_state_changed.emit("joined", "Loading %s" % mname)
	_apply_lobby(lobby)
	if map_name != mname:
		Events.open_menu.emit("load_map:" + mname)


@rpc("authority", "call_remote", "reliable")
func rpc_kicked(reason: String) -> void:
	Events.connection_state_changed.emit("error", reason)
	connect_target = ""
	shutdown()
	Events.open_menu.emit("main")


@rpc("authority", "call_remote", "reliable")
func rpc_lobby(d: Dictionary) -> void:
	_apply_lobby(d)


func _apply_lobby(d: Dictionary) -> void:
	for id in d:
		var iid := int(id)
		if not infos.has(iid):
			infos[iid] = {"name": "", "team": 0, "ready": false, "bot": false, "ping": 0, "token": "", "connected": true, "difficulty": 1}
		for k in d[id]:
			if k in ["stats", "alive", "money"]:
				var p: Player = players.get(iid)
				if p and not is_server():
					if k == "stats":
						p.stats = d[id][k]
					elif k == "money" and iid != local_id:
						p.money = d[id][k]
			else:
				infos[iid][k] = d[id][k]
	for id in infos.keys():
		if not d.has(id) and not d.has(str(id)):
			infos.erase(id)
	Events.lobby_updated.emit()


@rpc("authority", "call_remote", "reliable")
func rpc_spawn_player(id: int, d: Dictionary) -> void:
	if players.has(id):
		return
	var p := _spawn_player_node(id, d.name, d.team, d.bot)
	p.global_position = d.p
	p.yaw = d.yaw
	p.alive = d.alive
	p.stats = d.stats
	p.money = d.money
	if id == local_id:
		_setup_local_player(p)
	else:
		p.setup_visuals(false)


@rpc("authority", "call_remote", "reliable")
func rpc_despawn_player(id: int) -> void:
	_remove_player(id)


@rpc("authority", "call_remote", "reliable")
func rpc_reid_player(old_id: int, new_id: int) -> void:
	if old_id == local_id:
		return
	var p: Player = players.get(old_id)
	if p:
		players.erase(old_id)
		p.peer_id = new_id
		players[new_id] = p
	if infos.has(old_id):
		infos[new_id] = infos[old_id]
		infos.erase(old_id)


@rpc("authority", "call_remote", "reliable")
func rpc_player_team(id: int, team: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.team = team
		if p.model:
			p.model.queue_free()
			p.model = null
		if p.head:
			p.head.queue_free()
			p.head = null
			p.camera = null
			p.view_model = null
		p.setup_visuals(id == local_id)
	if infos.has(id):
		infos[id].team = team
	Events.player_team_changed.emit(id, team)


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_snapshot(bytes: PackedByteArray) -> void:
	_simulated_delivery(func(): _client_apply_snapshot(NetProtocol.unpack_snapshot(bytes)))


@rpc("authority", "call_remote", "reliable")
func rpc_match_state(d: Dictionary) -> void:
	Match.apply_state_dict(d)


@rpc("authority", "call_remote", "reliable")
func rpc_inventory(inv: Dictionary, money: int, armor: int, helmet: bool) -> void:
	var p := local_player()
	if p == null:
		return
	p.inventory.deserialize(inv)
	p.money = money
	p.armor = armor
	p.has_helmet = helmet
	if not p.inventory.has_slot(p.active_slot):
		p.active_slot = p.inventory.best_slot()
	Events.inventory_changed.emit(local_id)
	Events.money_changed.emit(local_id, money)


@rpc("authority", "call_remote", "reliable")
func rpc_event(kind: String, d: Dictionary) -> void:
	_handle_event(kind, d)


func _handle_event(kind: String, d: Dictionary) -> void:
	match kind:
		"kill":
			var v: Player = players.get(d.victim)
			if v:
				v.alive = false
				v.health = 0
				if v.model:
					v.model.set_alive(false)
				if d.victim == local_id:
					Events.local_player_died.emit()
			Events.player_killed.emit(d.victim, d.killer, d.weapon, d.headshot, d.get("assist", 0))
			if d.killer == local_id and d.victim != local_id:
				Audio.play_2d("ui/kill_confirm.wav", -6.0)
		"damage":
			Events.player_damaged.emit(d.victim, d.attacker, d.amount, d.zone, d.dir, d.armor)
			if d.victim == local_id:
				Audio.play_2d("ui/armor_hit.wav" if d.armor else "ui/damage_taken.wav", -8.0)
		"hit":
			Events.hit_confirmed.emit(d.victim, d.amount, d.headshot, d.killed)
			Audio.play_2d("ui/hitmarker.wav", -10.0, 1.3 if d.headshot else 1.0)
			if d.headshot:
				Audio.play_2d("weapons/headshot_ding.wav", -12.0)
		"spawn":
			var p: Player = players.get(d.id)
			if p:
				p.spawn_at(d.p, d.yaw, Match.rules)
				if d.id == local_id:
					history.clear()
					spectating = false
		"chat":
			Events.chat_message.emit(d.sender, d.team, d.text)
		"notify":
			Events.notification.emit(d.text, d.seconds)
		"announce":
			Events.announcer.emit(d.name)
		"flash":
			Events.flashed.emit(d.strength, d.duration)
		"footstep":
			Events.footstep.emit(d.id, d.p, d.surface, d.loud)
			var vol: float = -4.0 if d.loud else -16.0
			Audio.play_random_3d("foot/step_%s" % d.surface, 4, d.p, vol, 30.0 if d.loud else 12.0)
		"purchase_ok":
			Events.purchase_ok.emit(d.id)
			Audio.play_2d("ui/buy.wav", -8.0)
		"purchase_denied":
			Events.purchase_denied.emit(d.reason)
			Audio.play_2d("ui/deny.wav", -8.0)
		"bomb_planted":
			Events.bomb_planted.emit(d.site, d.planter)
		"bomb_defused":
			Events.bomb_defused.emit(d.defuser)
		"bomb_exploded":
			Events.bomb_exploded.emit()
			if Fx.instance:
				Fx.instance.explosion(d.p, 12.0)
			Audio.play_3d("grenades/bomb_explode.wav", d.p, 6.0, 1.0, 300.0)
		"bomb_dropped":
			Events.bomb_dropped.emit(d.p)
		"bomb_picked_up":
			Events.bomb_picked_up.emit(d.id)
		"surrender_vote":
			Events.surrender_vote_updated.emit(d.team, d.yes, d.needed)
		"surrender_started":
			Events.surrender_vote_started.emit(d.team)
		"landed":
			Audio.play_3d("foot/land_concrete.wav", d.p, -6.0)
		"fall_damage":
			Audio.play_3d("foot/fall_damage.wav", d.p, -2.0)


@rpc("authority", "call_remote", "unreliable")
func rpc_shot_fx(shooter: int, weapon_id: String, origin: Vector3, dir: Vector3, impact: Vector3, kind: int, normal: Vector3) -> void:
	if shooter == local_id:
		return
	_render_shot(shooter, weapon_id, origin, dir, impact, kind, normal)


@rpc("authority", "call_remote", "reliable")
func rpc_entity(id: int, action: String, d: Dictionary) -> void:
	match action:
		"spawn":
			_client_spawn_entity(id, d)
		"despawn":
			var e: Node = entities.get(id)
			if e:
				e.queue_free()
			entities.erase(id)
		"detonate", "bounce", "decoy_shot":
			_render_entity_event(id, action, d)


@rpc("authority", "call_remote", "unreliable")
func rpc_pong(t: float) -> void:
	ping_ms = int((Time.get_ticks_msec() / 1000.0 - t) * 1000.0)
	Events.latency_updated.emit(ping_ms)
	rpc_id(1, "rpc_report_ping", ping_ms)


# ============================================================================= players
func _spawn_player_node(id: int, pname: String, team: int, bot: bool) -> Player:
	var p := Player.new()
	p.setup(id, pname, team, bot)
	players[id] = p
	if world:
		world.add_child(p)
	else:
		add_child(p)
	p.global_position = Vector3(0, 50, 0)
	if is_server():
		p.landed.connect(func(speed): _server_on_landed(p, speed))
		p.footstep_taken.connect(func(loud): _server_on_footstep(p, loud))
		if bot:
			var brain_script := load("res://src/ai/BotBrain.gd")
			var brain: Node = brain_script.new()
			brain.name = "Brain"
			p.add_child(brain)
			brain.setup(p, int(Settings.get_value("gameplay", "bot_difficulty", 1)))
		elif id != local_id:
			p.setup_visuals(false)
	if is_server() and not bot and id != local_id and DisplayServer.get_name() != "headless":
		pass
	return p


func _setup_local_player(p: Player) -> void:
	p.setup_visuals(true)
	if local_controller == null:
		var lc_script := load("res://src/player/LocalController.gd")
		local_controller = lc_script.new()
		local_controller.name = "LocalController"
		add_child(local_controller)
	local_controller.attach(p)
	if spectator == null:
		var sp_script := load("res://src/player/Spectator.gd")
		spectator = sp_script.new()
		spectator.name = "Spectator"
		add_child(spectator)
	p.shot_fired.connect(func(wid, o, d, impact, kind): _render_shot(p.peer_id, wid, o, d, impact, kind, Vector3.UP))
	Events.local_player_ready.emit(p)


func _remove_player(id: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.queue_free()
	players.erase(id)
	infos.erase(id)
	input_queue.erase(id)
	last_cmds.erase(id)
	lagcomp.forget(id)
	remote_buffers.erase(id)
	Events.player_left.emit(id)
	Events.lobby_updated.emit()


func server_kick(id: int) -> void:
	if not is_server():
		return
	if id in remote_human_peers():
		rpc_id(id, "rpc_kicked", "Removed by server")
	for pid in remote_human_peers():
		if pid != id:
			rpc_id(pid, "rpc_despawn_player", id)
	_remove_player(id)
	_broadcast_lobby()


func server_add_bot(team: int = Teams.NONE, difficulty: int = -1) -> Player:
	if not is_server():
		return null
	var id := next_bot_id
	next_bot_id -= 1
	var pname := BotNames.pick(id)
	_server_register_player(id, pname, "", true)
	if team != Teams.NONE:
		server_set_team(id, team)
	if difficulty >= 0:
		infos[id].difficulty = difficulty
		var brain: Node = players[id].get_node_or_null("Brain")
		if brain:
			brain.set_difficulty(difficulty)
	return players[id]


func server_remove_bots() -> void:
	for id in players.keys().duplicate():
		if infos.has(id) and infos[id].bot:
			server_kick(id)


# ============================================================================= server loop
func _physics_process(dt: float) -> void:
	_process_inbound()
	if is_server():
		_server_tick(dt)
	elif is_client():
		_client_tick(dt)


func _server_tick(dt: float) -> void:
	server_tick += 1
	var now := Time.get_ticks_msec() / 1000.0
	for id in players.keys():
		var p: Player = players[id]
		if not is_instance_valid(p):
			continue
		var brain: Node = p.get_node_or_null("Brain")
		var cmds: Array = []
		if brain:
			cmds = [brain.think(dt, server_tick)]
		elif id == local_id and listen_server:
			if local_controller:
				cmds = [local_controller.build_cmd(server_tick, server_tick)]
		else:
			var q: Array = input_queue.get(id, [])
			var n: int = mini(q.size(), NetValidation.MAX_CMDS_PER_TICK)
			if n == 0 and last_cmds.has(id):
				# no input this tick: keep moving with the last known intent, but release triggers
				var c: InputCmd = last_cmds[id].duplicate_cmd()
				c.tick += 1
				c.buttons &= ~(InputCmd.BTN_FIRE | InputCmd.BTN_ALT_FIRE | InputCmd.BTN_JUMP)
				cmds = [c]
			else:
				for i in n:
					cmds.append(q.pop_front())
				input_queue[id] = q
		for cmd in cmds:
			p.process_cmd(cmd, dt, true)
			last_cmds[id] = cmd
		lagcomp.record(p, server_tick)
		if p.alive and p.global_position.y < -30.0:
			p.server_die(0, "world", false)
	# reconnect grace expiry
	for id in pending_disconnect.keys():
		if now - pending_disconnect[id] > RECONNECT_GRACE:
			pending_disconnect.erase(id)
			for pid in remote_human_peers():
				rpc_id(pid, "rpc_despawn_player", id)
			_remove_player(id)
			_broadcast_lobby()
	Match.server_tick(dt)
	if server_tick % SNAPSHOT_EVERY_TICKS == 0:
		_server_broadcast_snapshot()


func _server_broadcast_snapshot() -> void:
	var states := []
	for p in players.values():
		if is_instance_valid(p):
			states.append(p.snapshot_state())
	var ents := []
	for eid in entities:
		var e: Node = entities[eid]
		if e is RigidBody3D:
			ents.append({"id": eid, "type": _entity_type(e), "p": e.global_position, "v": e.linear_velocity, "weapon": e.weapon_id if e is WeaponPickup else e.cfg.id})
	var bytes := NetProtocol.pack_snapshot(server_tick, states, ents)
	for id in remote_human_peers():
		if sim_loss > 0.0 and randf() < sim_loss:
			continue
		rpc_id(id, "rpc_snapshot", bytes)


func _server_on_landed(p: Player, speed: float) -> void:
	var dmg := DamageModel.fall_damage(Match.rules, speed)
	if dmg > 0:
		p.server_apply_damage(dmg, 0, 0, "fall", DamageModel.Zone.LEG, Vector3.DOWN, false)
		broadcast_event("fall_damage", {"p": p.global_position})
	elif speed > 4.0:
		broadcast_event("landed", {"p": p.global_position})
		Match.server_report_noise(p.global_position, p.team, "landing")


func _server_on_footstep(p: Player, loud: bool) -> void:
	var surface := "concrete"
	if p.global_position.y > 2.5:
		surface = "metal"
	broadcast_event("footstep", {"id": p.peer_id, "p": p.global_position, "surface": surface, "loud": loud})
	if loud:
		Match.server_report_noise(p.global_position, p.team, "footstep")


func broadcast_event(kind: String, d: Dictionary) -> void:
	if not is_server():
		return
	for id in remote_human_peers():
		rpc_id(id, "rpc_event", kind, d)
	if listen_server:
		_handle_event(kind, d)


func send_event_to(id: int, kind: String, d: Dictionary) -> void:
	if not is_server() or not infos.has(id) or infos[id].bot:
		return
	if id == local_id:
		_handle_event(kind, d)
	elif id in remote_human_peers():
		rpc_id(id, "rpc_event", kind, d)


# ============================================================================= server: combat
func server_resolve_shot(shooter: Player, cfg: WeaponConfig, origin: Vector3, dir: Vector3, view_tick: int, cmd_tick: int, pellet: int) -> void:
	var space := shooter.get_world_3d().direct_space_state
	var max_range := cfg.max_range * 1.5
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, 1)
	var wall := space.intersect_ray(q)
	var wall_dist := origin.distance_to(wall.position) if not wall.is_empty() else max_range
	var best_dist := wall_dist
	var victim: Player = null
	var victim_zone := DamageModel.Zone.NONE
	var hit_point: Vector3 = wall.position if not wall.is_empty() else origin + dir * max_range
	for p in players.values():
		if p == shooter or not p.alive:
			continue
		if not Match.rules.friendly_fire and p.team == shooter.team:
			continue
		var rec := lagcomp.pose_at(p.peer_id, view_tick, server_tick)
		var xform := lagcomp.transform_for(rec) if not rec.is_empty() else Transform3D(Basis(Vector3.UP, p.yaw), p.global_position)
		var crouch: bool = rec.crouch if not rec.is_empty() else p.crouching
		var r := Hitboxes.raycast(xform, crouch, origin, dir, best_dist)
		if r.hit and r.distance < best_dist:
			best_dist = r.distance
			victim = p
			victim_zone = r.zone
			hit_point = r.point
	var kind := Player.IMPACT_WORLD if not wall.is_empty() else Player.IMPACT_NONE
	var normal: Vector3 = wall.normal if not wall.is_empty() else Vector3.UP
	if victim:
		var res := DamageModel.compute(cfg, victim_zone, best_dist, victim.armor, victim.has_helmet)
		kind = Player.IMPACT_HEADSHOT if res.headshot else Player.IMPACT_PLAYER
		var killed: bool = victim.server_apply_damage(res.damage, res.armor_damage, shooter.peer_id, cfg.id, victim_zone, dir, res.armor_hit)
		shooter.stats.damage += res.damage
		send_event_to(shooter.peer_id, "hit", {"victim": victim.peer_id, "amount": res.damage, "headshot": res.headshot, "killed": killed})
		normal = -dir
	Match.server_report_noise(origin, shooter.team, "gunfire")
	# effects for everyone (the shooter predicted its own)
	for id in remote_human_peers():
		if id != shooter.peer_id:
			rpc_id(id, "rpc_shot_fx", shooter.peer_id, cfg.id, origin, dir, hit_point, kind, normal)
	if listen_server and shooter.peer_id != local_id:
		_render_shot(shooter.peer_id, cfg.id, origin, dir, hit_point, kind, normal)


func server_resolve_melee(attacker: Player, cfg: WeaponConfig, origin: Vector3, dir: Vector3, heavy: bool, view_tick: int) -> void:
	var best: Player = null
	var best_dist := cfg.melee_range
	var zone := DamageModel.Zone.CHEST
	for p in players.values():
		if p == attacker or not p.alive:
			continue
		if not Match.rules.friendly_fire and p.team == attacker.team:
			continue
		var rec := lagcomp.pose_at(p.peer_id, view_tick, server_tick)
		var xform := lagcomp.transform_for(rec) if not rec.is_empty() else Transform3D(Basis(Vector3.UP, p.yaw), p.global_position)
		var r := Hitboxes.raycast(xform, p.crouching, origin, dir, cfg.melee_range)
		if r.hit and r.distance < best_dist:
			best_dist = r.distance
			best = p
			zone = r.zone
	Match.server_report_noise(origin, attacker.team, "melee")
	if best == null:
		broadcast_event("notify", {"text": "", "seconds": 0.0}) if false else null
		return
	var dmg := cfg.melee_damage_heavy if heavy else cfg.melee_damage_light
	var behind := best.aim_direction().dot(dir) > 0.5
	if behind and heavy:
		dmg *= cfg.backstab_mult
	var killed := best.server_apply_damage(int(dmg), 0, attacker.peer_id, cfg.id, zone, dir, false)
	send_event_to(attacker.peer_id, "hit", {"victim": best.peer_id, "amount": int(dmg), "headshot": false, "killed": killed})
	for id in remote_human_peers():
		rpc_id(id, "rpc_shot_fx", attacker.peer_id, cfg.id, origin, dir, best.global_position + Vector3(0, 1.2, 0), Player.IMPACT_PLAYER, -dir)


func server_throw_grenade(thrower: Player, cfg: WeaponConfig, origin: Vector3, vel: Vector3) -> void:
	var g := Grenade.new()
	g.setup(cfg, thrower.peer_id, thrower.team, true)
	g.entity_id = _alloc_entity_id()
	g.name = "Entity_%d" % g.entity_id
	(world if world else self).add_child(g)
	g.global_position = origin
	g.linear_velocity = vel
	g.angular_velocity = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	entities[g.entity_id] = g
	_broadcast_entity(g.entity_id, "spawn", _entity_spawn_dict(g))


func server_spawn_area_effect(kind: String, pos: Vector3, radius: float, duration: float, owner: int, team: int) -> void:
	var a := AreaEffect.new()
	a.entity_id = _alloc_entity_id()
	a.name = "Entity_%d" % a.entity_id
	(world if world else self).add_child(a)
	a.global_position = pos
	a.setup(kind, radius, duration, owner, team, true)
	entities[a.entity_id] = a
	_broadcast_entity(a.entity_id, "spawn", _entity_spawn_dict(a))


func server_drop_weapon(p: Player, slot: int, force_dir: Vector3 = Vector3.ZERO) -> void:
	if slot == Inventory.SLOT_MELEE:
		return
	var ws: WeaponState = p.inventory.get_active(slot)
	if ws == null:
		return
	var id := ws.cfg.id
	p.inventory.remove(slot, id if slot == Inventory.SLOT_GRENADE else "")
	if slot == p.active_slot:
		p.switch_to_slot(p.inventory.best_slot())
	var dir := p.aim_direction() if force_dir == Vector3.ZERO else force_dir
	_server_spawn_pickup(id, ws.ammo, ws.reserve, p.eye_position() + dir * 0.4, dir * 4.0 + Vector3.UP * 1.5 + p.velocity)
	if id == "bomb":
		Match.server_bomb_dropped(p)
	server_sync_inventory(p)


func server_drop_all_on_death(p: Player) -> void:
	var slot := Inventory.SLOT_PRIMARY if p.inventory.has_slot(Inventory.SLOT_PRIMARY) else Inventory.SLOT_SECONDARY
	if p.inventory.has_slot(slot):
		server_drop_weapon(p, slot, Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized())
	if p.inventory.has_bomb():
		server_drop_weapon(p, Inventory.SLOT_BOMB, Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)).normalized())


func _server_spawn_pickup(id: String, ammo: int, reserve: int, pos: Vector3, vel: Vector3) -> void:
	var pk := WeaponPickup.new()
	pk.setup(id, ammo, reserve, true)
	pk.entity_id = _alloc_entity_id()
	pk.name = "Entity_%d" % pk.entity_id
	(world if world else self).add_child(pk)
	pk.global_position = pos
	pk.linear_velocity = vel
	entities[pk.entity_id] = pk
	_broadcast_entity(pk.entity_id, "spawn", _entity_spawn_dict(pk))


func server_try_auto_pickup(p: Player, pk: WeaponPickup) -> void:
	var cfg := WeaponDB.get_config(pk.weapon_id)
	if cfg == null:
		return
	if cfg.id == "bomb" and p.team != Teams.ATTACKERS:
		return
	if cfg.slot in ["primary", "secondary", "bomb"] and p.inventory.has_slot({"primary": 0, "secondary": 1, "bomb": 4}[cfg.slot]):
		return
	if cfg.slot == "grenade" and (p.inventory.find_grenade(cfg.id) != null or p.inventory.grenade_total() >= 4):
		return
	if p.inventory.give(cfg):
		var ws: WeaponState = p.inventory.find_grenade(cfg.id) if cfg.slot == "grenade" else p.inventory.get_active({"primary": 0, "secondary": 1, "bomb": 4}[cfg.slot])
		if ws and cfg.slot != "grenade":
			ws.ammo = pk.ammo
			ws.reserve = pk.reserve
		if cfg.id == "bomb":
			Match.server_bomb_picked_up(p)
		if cfg.slot == "primary" and p.active_slot != Inventory.SLOT_PRIMARY and p.active_config() and p.active_config().category != "grenade":
			p.switch_to_slot(Inventory.SLOT_PRIMARY)
		server_despawn_entity(pk.entity_id)
		server_sync_inventory(p)


func server_try_pickup_swap(p: Player) -> void:
	# "use" while looking at a pickup: drop the weapon in that slot and take the pickup
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.eye_position(), p.eye_position() + p.aim_direction() * 2.5, 16)
	var r := space.intersect_ray(q)
	if r.is_empty() or not (r.collider is WeaponPickup):
		return
	var pk: WeaponPickup = r.collider
	var cfg := WeaponDB.get_config(pk.weapon_id)
	if cfg == null or cfg.slot not in ["primary", "secondary"]:
		return
	var slot := Inventory.SLOT_PRIMARY if cfg.slot == "primary" else Inventory.SLOT_SECONDARY
	if p.inventory.has_slot(slot):
		server_drop_weapon(p, slot)
	server_try_auto_pickup(p, pk)


func server_sync_inventory(p: Player) -> void:
	if p.is_bot:
		return
	if p.peer_id == local_id:
		Events.inventory_changed.emit(local_id)
		Events.money_changed.emit(local_id, p.money)
	elif p.peer_id in remote_human_peers():
		rpc_id(p.peer_id, "rpc_inventory", p.inventory.serialize(), p.money, p.armor, p.has_helmet)


func server_broadcast_damage(victim: Player, attacker_id: int, amount: int, zone: int, dir: Vector3, armor_hit: bool) -> void:
	broadcast_event("damage", {"victim": victim.peer_id, "attacker": attacker_id, "amount": amount, "zone": zone, "dir": dir, "armor": armor_hit})


func server_on_player_died(victim: Player, killer_id: int, weapon_id: String, headshot: bool, assist: int) -> void:
	server_drop_all_on_death(victim)
	Match.server_on_kill(victim, killer_id, weapon_id, headshot, assist)
	broadcast_event("kill", {"victim": victim.peer_id, "killer": killer_id, "weapon": weapon_id, "headshot": headshot, "assist": assist})


func server_flash_player(p: Player, strength: float, duration: float) -> void:
	p.flash_end = Time.get_ticks_msec() / 1000.0 + duration
	send_event_to(p.peer_id, "flash", {"strength": strength, "duration": duration})


func server_spawn_player(p: Player, pos: Vector3, yaw: float) -> void:
	p.spawn_at(pos, yaw, Match.rules)
	broadcast_event("spawn", {"id": p.peer_id, "p": pos, "yaw": yaw})
	if p.peer_id == local_id:
		history.clear()
		spectating = false


# ============================================================================= entities
func _alloc_entity_id() -> int:
	var id := next_entity_id
	next_entity_id = (next_entity_id % 65000) + 1
	return id


func _entity_type(e: Node) -> int:
	if e is Grenade:
		return Grenade.TYPE_GRENADE
	if e is WeaponPickup:
		return WeaponPickup.TYPE_PICKUP
	return AreaEffect.TYPE_AREA


func _entity_spawn_dict(e: Node) -> Dictionary:
	if e is Grenade:
		return {"type": Grenade.TYPE_GRENADE, "weapon": e.cfg.id, "p": e.global_position, "v": e.linear_velocity, "owner": e.owner_id, "team": e.owner_team}
	if e is WeaponPickup:
		return {"type": WeaponPickup.TYPE_PICKUP, "weapon": e.weapon_id, "p": e.global_position, "v": e.linear_velocity}
	return {"type": AreaEffect.TYPE_AREA, "kind": e.kind, "p": e.global_position, "radius": e.radius, "duration": e.remaining, "owner": e.owner_id, "team": e.owner_team}


func _broadcast_entity(id: int, action: String, d: Dictionary) -> void:
	for pid in remote_human_peers():
		rpc_id(pid, "rpc_entity", id, action, d)
	if listen_server and action != "spawn" and action != "despawn":
		_render_entity_event(id, action, d)


func server_entity_event(id: int, action: String, d: Dictionary) -> void:
	_broadcast_entity(id, action, d)


func server_despawn_entity(id: int) -> void:
	var e: Node = entities.get(id)
	if e:
		e.queue_free()
	entities.erase(id)
	_broadcast_entity(id, "despawn", {})


func _client_spawn_entity(id: int, d: Dictionary) -> void:
	if entities.has(id) or world == null:
		return
	var node: Node3D
	match int(d.type):
		Grenade.TYPE_GRENADE:
			var g := Grenade.new()
			g.setup(WeaponDB.get_config(d.weapon), d.owner, d.team, false)
			node = g
		WeaponPickup.TYPE_PICKUP:
			var pk := WeaponPickup.new()
			pk.setup(d.weapon, 0, 0, false)
			node = pk
		_:
			var a := AreaEffect.new()
			node = a
			world.add_child(a)
			a.global_position = d.p
			a.setup(d.kind, d.radius, d.duration, d.owner, d.team, false)
			a.entity_id = id
			entities[id] = a
			return
	node.name = "Entity_%d" % id
	node.set("entity_id", id)
	world.add_child(node)
	node.global_position = d.p
	entities[id] = node


func _render_entity_event(id: int, action: String, d: Dictionary) -> void:
	if Fx.instance == null:
		return
	match action:
		"bounce":
			Audio.play_3d("grenades/bounce.wav", d.p, -10.0, randf_range(0.9, 1.1), 25.0)
		"decoy_shot":
			Audio.play_3d("grenades/decoy_shot_%d.wav" % (randi() % 3), d.p, -2.0, 1.0, 120.0)
			Fx.instance.muzzle_flash(d.p + Vector3(0, 0.1, 0), Vector3.UP)
		"detonate":
			match d.kind:
				"frag":
					Fx.instance.explosion(d.p, 6.0)
					Audio.play_3d("grenades/frag_explode.wav", d.p, 4.0, 1.0, 200.0)
				"flash":
					Fx.instance.explosion(d.p, 3.0, Color(1, 1, 1))
					Audio.play_3d("grenades/flash_pop.wav", d.p, 2.0, 1.0, 150.0)
				"decoy":
					Fx.instance.explosion(d.p, 1.0, Color(1, 0.9, 0.5))
					Audio.play_3d("grenades/bounce.wav", d.p, 0.0, 0.6, 40.0)


# ============================================================================= client loop
func _client_tick(dt: float) -> void:
	if _reconnect_timer > 0.0:
		_reconnect_timer -= dt
		if _reconnect_timer <= 0.0:
			var parts := connect_target.split(":")
			var pn := local_player_name
			var target := connect_target
			shutdown()
			connect_target = target
			join(parts[0], int(parts[1]), pn)
		return
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ping_timer += dt
	if _ping_timer > 1.0:
		_ping_timer = 0.0
		rpc_id(1, "rpc_ping", Time.get_ticks_msec() / 1000.0)
	var p := local_player()
	if p == null or local_controller == null:
		return
	client_tick += 1
	var cmd: InputCmd = local_controller.build_cmd(client_tick, last_snapshot_tick)
	# send the last few commands redundantly so a lost packet does not stall the server
	var buf := StreamPeerBuffer.new()
	var recent: Array = []
	for i in range(max(history.size() - 2, 0), history.size()):
		recent.append(history[i].cmd)
	recent.append(cmd)
	buf.put_u8(recent.size())
	for c in recent:
		c.pack(buf)
	if not (sim_loss > 0.0 and randf() < sim_loss):
		rpc_id(1, "rpc_input", buf.data_array)
	if p.alive:
		p.process_cmd(cmd, dt, false)
	history.append({"tick": client_tick, "cmd": cmd, "state": p.get_state()})
	while history.size() > 128:
		history.pop_front()
	_client_interpolate_remote(dt)


func _client_apply_snapshot(snap: Dictionary) -> void:
	if snap.tick <= last_snapshot_tick:
		return
	last_snapshot_tick = snap.tick
	for s in snap.players:
		var p: Player = players.get(s.id)
		if p == null:
			continue
		_apply_common_state(p, s)
		if s.id == local_id:
			_reconcile_local(p, s)
		else:
			var buf: Array = remote_buffers.get(s.id, [])
			buf.append({"tick": snap.tick, "p": s.p, "yaw": s.yaw, "pitch": s.pitch, "v": s.v, "crouch": s.crouch})
			while buf.size() > 12:
				buf.pop_front()
			remote_buffers[s.id] = buf
	var seen := {}
	for e in snap.entities:
		seen[e.id] = true
		var node: Node = entities.get(e.id)
		if node is RigidBody3D:
			node.global_position = node.global_position.lerp(e.p, 0.6)
			node.linear_velocity = e.v


func _apply_common_state(p: Player, s: Dictionary) -> void:
	var was_alive := p.alive
	p.alive = s.alive
	p.health = s.hp
	p.armor = s.armor
	p.has_helmet = s.helmet
	p.inventory.has_kit = s.kit
	p.plant_progress = s.progress
	p.defuse_progress = s.progress
	p.planting = s.progress > 0.0 and p.team == Teams.ATTACKERS
	p.defusing = s.progress > 0.0 and p.team == Teams.DEFENDERS
	if p.peer_id != local_id:
		p.zoomed = s.zoomed
		p.on_ladder = s.ladder
		p.was_on_floor = s.floor
		p.crouching = s.crouch > 0.5
		p.crouch_amount = s.crouch
		# remote weapon display
		if not s.weapon.is_empty():
			var cur := p.active_config()
			if cur == null or cur.id != s.weapon:
				var cfg := WeaponDB.get_config(s.weapon)
				if cfg:
					p.inventory.slots = [null, null, null, [], null]
					p.inventory.give(cfg)
					p.active_slot = {"primary": 0, "secondary": 1, "melee": 2, "grenade": 3, "bomb": 4}.get(cfg.slot, 2)
	if s.alive and not was_alive and p.model:
		p.model.set_alive(true)
	if not s.alive and was_alive and p.model:
		p.model.set_alive(false)


func _reconcile_local(p: Player, s: Dictionary) -> void:
	last_ack_tick = s.tick
	var w := p.active_weapon()
	if w and w.cfg.id == s.weapon:
		w.ammo = s.ammo
		w.reserve = s.reserve
	if not p.alive:
		p.global_position = s.p
		return
	# find our predicted state at the acked tick
	var idx := -1
	for i in range(history.size()):
		if history[i].tick == s.tick:
			idx = i
			break
	if idx < 0:
		if history.is_empty() or s.tick > history[-1].tick:
			p.global_position = s.p
			p.velocity = s.v
		return
	var predicted: Dictionary = history[idx].state
	var err: float = predicted.p.distance_to(s.p)
	if err > PREDICTION_TOLERANCE:
		var st := p.get_state()
		st.p = s.p
		st.v = s.v
		p.set_state(st)
		p.recoil_offset = s.recoil
		for i in range(idx + 1, history.size()):
			var cmd: InputCmd = history[i].cmd
			p.simulate(cmd, 1.0 / Engine.physics_ticks_per_second)
			history[i].state = p.get_state()
	history = history.slice(idx + 1)


func _client_interpolate_remote(dt: float) -> void:
	var render_tick := last_snapshot_tick - INTERP_DELAY_TICKS * SNAPSHOT_EVERY_TICKS
	for id in remote_buffers:
		var p: Player = players.get(id)
		if p == null:
			continue
		var buf: Array = remote_buffers[id]
		if buf.size() < 2:
			if buf.size() == 1:
				p.global_position = buf[0].p
				p.yaw = buf[0].yaw
				p.pitch = buf[0].pitch
			continue
		var a: Dictionary = buf[0]
		var b: Dictionary = buf[1]
		for i in range(buf.size() - 1):
			if buf[i].tick <= render_tick and buf[i + 1].tick >= render_tick:
				a = buf[i]
				b = buf[i + 1]
				break
			if buf[i + 1].tick < render_tick:
				a = buf[i]
				b = buf[i + 1]
		var span: int = b.tick - a.tick
		var t: float = 1.0 if span <= 0 else clampf(float(render_tick - a.tick) / float(span), 0.0, 1.2)
		p.global_position = a.p.lerp(b.p, t)
		p.yaw = lerp_angle(a.yaw, b.yaw, t)
		p.pitch = lerpf(a.pitch, b.pitch, t)
		p.velocity = b.v


# ============================================================================= rendering helpers
func _render_shot(shooter_id: int, weapon_id: String, origin: Vector3, dir: Vector3, impact: Vector3, kind: int, normal: Vector3) -> void:
	if Fx.instance == null:
		return
	var cfg := WeaponDB.get_config(weapon_id)
	if cfg == null:
		return
	var p: Player = players.get(shooter_id)
	if cfg.category == "melee":
		Audio.play_3d("weapons/knife_swing.wav", origin, -6.0, 1.0, 20.0)
		if kind == Player.IMPACT_PLAYER:
			Audio.play_3d("weapons/knife_hit.wav", impact, -4.0)
			Fx.instance.impact(impact, normal, kind)
		return
	if cfg.category == "grenade":
		Audio.play_3d("grenades/pin_pull.wav", origin, -10.0, 1.0, 10.0)
		return
	var muzzle := origin + dir * 0.6
	var eject_xf := Transform3D(Basis.looking_at(dir), origin + dir * 0.3)
	if p and p.peer_id == local_id and p.view_model:
		muzzle = p.view_model.muzzle_position()
		eject_xf = p.view_model.eject_transform()
	elif p and p.model:
		muzzle = origin + dir * 0.7 + Vector3(0, -0.15, 0)
	Fx.instance.muzzle_flash(muzzle, dir)
	if cfg.tracer and randf() < 0.65:
		Fx.instance.tracer(muzzle, impact if kind != Player.IMPACT_NONE else origin + dir * 60.0)
	if cfg.ejects_shells:
		Fx.instance.eject_shell(eject_xf)
	if kind != Player.IMPACT_NONE:
		Fx.instance.impact(impact, normal, kind, impact.y > 2.5)
	var dist := 0.0
	var lp := local_player()
	if lp:
		dist = lp.global_position.distance_to(origin)
	var clip := "weapons/shot_%s.wav" % cfg.sound_class
	if dist > 45.0:
		clip = "weapons/shot_%s_distant.wav" % cfg.sound_class
	Audio.play_3d(clip, muzzle, 2.0 if shooter_id == local_id else 0.0, randf_range(0.96, 1.04), 250.0)
	if lp and shooter_id != local_id and lp.alive and dist > 3.0:
		# bullet whiz for near misses
		var to_me := lp.eye_position() - origin
		var closest := origin + dir * clampf(to_me.dot(dir), 0.0, 400.0)
		if closest.distance_to(lp.eye_position()) < 1.5:
			Audio.play_3d("weapons/bullet_whiz.wav", closest, -6.0, randf_range(0.9, 1.1), 10.0)


# ============================================================================= network simulation
func _simulated_delivery(cb: Callable) -> void:
	if sim_latency_ms <= 0 and sim_jitter_ms <= 0:
		cb.call()
		return
	if sim_loss > 0.0 and randf() < sim_loss:
		return
	var delay := (sim_latency_ms + randf_range(0, sim_jitter_ms)) / 1000.0
	_inbound.append([Time.get_ticks_msec() / 1000.0 + delay, cb])


func _process_inbound() -> void:
	if _inbound.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var remaining := []
	for item in _inbound:
		if item[0] <= now:
			item[1].call()
		else:
			remaining.append(item)
	_inbound = remaining


func set_network_sim(latency_ms: int, loss: float, jitter_ms: int) -> void:
	sim_latency_ms = latency_ms
	sim_loss = clampf(loss, 0.0, 0.9)
	sim_jitter_ms = jitter_ms
