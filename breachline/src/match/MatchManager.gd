extends Node
## Autoload "Match": competitive bomb-defusal rules. Server mutates state; clients receive
## state_dict() through Net and only render. Round flow:
## LOBBY -> WARMUP -> FREEZE -> LIVE -> (PLANTED) -> ROUND_END -> FREEZE | HALFTIME | MATCH_END

enum State { LOBBY, WARMUP, FREEZE, LIVE, PLANTED, ROUND_END, HALFTIME, MATCH_END }

var rules: MatchRules
var economy_cfg: EconomyConfig
var economy: Economy
var state: int = State.LOBBY
var time_left: float = 0.0
var round_number: int = 0
var score := {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
var loss_streak := {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
var round_winner: int = Teams.NONE
var round_end_reason := ""
var overtime := false
var overtime_block := 0
var bomb_state := "carried"            # carried | dropped | planted | defused | exploded
var bomb_site := ""
var bomb_position := Vector3.ZERO
var bomb_carrier_id := 0
var bomb_timer := 0.0
var bomb_planter_id := 0
var bomb_planted_this_round := false
var first_half_attackers: Array = []   # peer ids that started as attackers (for halftime swap)
var surrender_votes := {}              # team -> {id: bool}
var rematch_votes := {}
var match_winner: int = Teams.NONE
var round_mvp_id := 0
var layout: Dictionary = {}
var noise_events: Array = []           # for bots: {pos, team, kind, time}
var buy_time_left := 0.0
var bomb_node: Node3D
var round_kills: Dictionary = {}
var started_once := false
var swapped_at_halftime := false
var ot_swapped := false


func _ready() -> void:
	rules = load("res://src/data/rules_competitive.tres")
	economy_cfg = load("res://src/data/economy/economy.tres")
	economy = Economy.new(economy_cfg)
	for e in rules.validate():
		push_error("MatchRules: " + e)
	for e in economy_cfg.validate():
		push_error("EconomyConfig: " + e)
	_apply_settings_overrides()


var lock_rules := false   # tests set rules directly and do not want settings applied


func _apply_settings_overrides() -> void:
	if lock_rules:
		return
	var mr := int(Settings.get_value("gameplay", "max_rounds", 24))
	if mr >= 2 and mr % 2 == 0:
		rules.max_rounds = mr
		rules.rounds_to_win = mr / 2 + 1
	rules.overtime_enabled = bool(Settings.get_value("gameplay", "overtime", true))
	rules.friendly_fire = bool(Settings.get_value("gameplay", "friendly_fire", false))


func state_name() -> String:
	return State.keys()[state].capitalize()


func set_layout(l: Dictionary) -> void:
	layout = l


# ---------------------------------------------------------------------------- queries
func team_count(t: int) -> int:
	var n := 0
	for i: Dictionary in Net.infos.values():
		if i.team == t:
			n += 1
	return n


func pick_team_for_new_player() -> int:
	return Teams.ATTACKERS if team_count(Teams.ATTACKERS) <= team_count(Teams.DEFENDERS) else Teams.DEFENDERS


func alive_count(t: int) -> int:
	var n := 0
	for p: Player in Net.players.values():
		if p.team == t and p.alive:
			n += 1
	return n


func site_at(pos: Vector3) -> String:
	for k in layout.get("sites", {}):
		var s: Dictionary = layout.sites[k]
		var c := Vector3(s.pos[0], s.pos[1], s.pos[2])
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s.radius) and abs(pos.y - c.y) < 3.0:
			return k
	return ""


func in_buy_zone(p: Player) -> bool:
	var key := "attackers" if p.team == Teams.ATTACKERS else "defenders"
	var z: Dictionary = layout.get("buy_zones", {}).get(key, {})
	if z.is_empty():
		return true
	var pos := p.global_position
	return pos.x >= z.min[0] and pos.x <= z.max[0] and pos.z >= z.min[2] and pos.z <= z.max[2]


func callout_at(pos: Vector3) -> String:
	var best := ""
	var best_area := INF
	for name in layout.get("callouts", {}):
		var z: Dictionary = layout.callouts[name]
		if pos.x >= z.min[0] and pos.x <= z.max[0] and pos.z >= z.min[2] and pos.z <= z.max[2]:
			var area: float = (z.max[0] - z.min[0]) * (z.max[2] - z.min[2])
			if area < best_area:
				best_area = area
				best = name
	return best


func can_buy() -> bool:
	return state == State.FREEZE or (state == State.LIVE and buy_time_left > 0.0) or state == State.WARMUP


func can_plant() -> bool:
	return state == State.LIVE


func bomb_planted() -> bool:
	return bomb_state == "planted"


func rules_dict() -> Dictionary:
	return {"max_rounds": rules.max_rounds, "rounds_to_win": rules.rounds_to_win, "round_time": rules.round_time, "freeze_time": rules.freeze_time,
		"buy_time": rules.buy_time, "bomb_timer": rules.bomb_timer, "plant_time": rules.plant_time, "defuse_time": rules.defuse_time,
		"kit_defuse_time": rules.kit_defuse_time, "overtime_enabled": rules.overtime_enabled, "overtime_rounds": rules.overtime_rounds,
		"friendly_fire": rules.friendly_fire, "team_size": rules.team_size, "max_players": rules.max_players}


func apply_rules_dict(d: Dictionary) -> void:
	for k in d:
		rules.set(k, d[k])


func state_dict() -> Dictionary:
	return {"state": state, "time": time_left, "round": round_number, "score_a": score[Teams.ATTACKERS], "score_d": score[Teams.DEFENDERS],
		"winner": round_winner, "reason": round_end_reason, "ot": overtime, "ot_block": overtime_block, "bomb": bomb_state, "site": bomb_site,
		"bomb_pos": bomb_position, "carrier": bomb_carrier_id, "bomb_timer": bomb_timer, "planted_round": bomb_planted_this_round,
		"match_winner": match_winner, "mvp": round_mvp_id, "buy_time": buy_time_left}


func apply_state_dict(d: Dictionary) -> void:
	var old_state := state
	var old_round := round_number
	var old_bomb: String = bomb_state
	state = d.state
	time_left = d.time
	round_number = d.round
	score[Teams.ATTACKERS] = d.score_a
	score[Teams.DEFENDERS] = d.score_d
	round_winner = d.winner
	round_end_reason = d.reason
	overtime = d.ot
	overtime_block = d.ot_block
	bomb_state = d.bomb
	bomb_site = d.site
	bomb_position = d.bomb_pos
	bomb_carrier_id = d.carrier
	bomb_timer = d.bomb_timer
	bomb_planted_this_round = d.planted_round
	match_winner = d.match_winner
	round_mvp_id = d.mvp
	buy_time_left = d.buy_time
	if not Net.is_server():
		_update_bomb_node()
	Events.match_state_changed.emit(state, time_left)
	Events.score_changed.emit(score[Teams.ATTACKERS], score[Teams.DEFENDERS])
	if state != old_state:
		_on_state_entered_presentation(old_state)
	if round_number != old_round and state == State.FREEZE:
		Events.round_started.emit(round_number)


func _on_state_entered_presentation(old_state: int) -> void:
	match state:
		State.LIVE:
			if old_state == State.FREEZE:
				Events.announcer.emit("round_start")
				Audio.play_2d("ui/round_start.wav", -6.0)
		State.ROUND_END:
			Events.round_ended.emit(round_winner, round_end_reason)
			var lp := Net.local_player()
			if lp and lp.team in [Teams.ATTACKERS, Teams.DEFENDERS]:
				Audio.play_2d("ui/round_win.wav" if lp.team == round_winner else "ui/round_lose.wav", -6.0)
			Events.announcer.emit("attackers_win" if round_winner == Teams.ATTACKERS else "defenders_win")
		State.HALFTIME:
			Events.halftime.emit()
			Events.announcer.emit("halftime")
		State.MATCH_END:
			Events.match_ended.emit(match_winner)


func _broadcast_state() -> void:
	if Net.is_server():
		var d := state_dict()
		for id in Net.remote_human_peers():
			Net.rpc_id(id, "rpc_match_state", d)
		apply_state_dict(d)


# ---------------------------------------------------------------------------- server: lobby & flow
func server_check_ready() -> void:
	if state != State.LOBBY:
		return
	var humans := 0
	var ready := 0
	for i: Dictionary in Net.infos.values():
		if i.bot or not i.connected or i.team == Teams.SPECTATOR:
			continue
		humans += 1
		if i.ready:
			ready += 1
	if humans > 0 and ready == humans:
		server_start_match()


func server_start_match() -> void:
	if not Net.is_server():
		return
	_apply_settings_overrides()
	round_number = 0
	score = {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
	loss_streak = {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
	overtime = false
	overtime_block = 0
	match_winner = Teams.NONE
	swapped_at_halftime = false
	surrender_votes.clear()
	rematch_votes.clear()
	started_once = true
	first_half_attackers.clear()
	for id in Net.infos:
		if Net.infos[id].team == Teams.ATTACKERS:
			first_half_attackers.append(id)
	for p: Player in Net.players.values():
		p.stats = {"kills": 0, "deaths": 0, "assists": 0, "score": 0, "mvps": 0, "damage": 0, "headshots": 0}
		p.money = economy_cfg.start_money
		p.full_reset_inventory()
	_enter_state(State.WARMUP, rules.warmup_time if rules.warmup_time > 0 else 0.1)
	_spawn_all(true)


func server_late_join(p: Player) -> void:
	p.money = economy_cfg.start_money if not overtime else economy_cfg.overtime_start_money
	p.full_reset_inventory()
	if state == State.WARMUP:
		_spawn_player(p)
	Net.server_sync_inventory(p)


func _enter_state(s: int, t: float) -> void:
	state = s
	time_left = t
	match s:
		State.FREEZE:
			buy_time_left = rules.freeze_time + rules.buy_time
		State.LIVE:
			if buy_time_left <= 0.0:
				buy_time_left = 0.0
	_broadcast_state()


func server_tick(dt: float) -> void:
	if state == State.LOBBY:
		return
	time_left -= dt
	if buy_time_left > 0.0 and state in [State.FREEZE, State.LIVE]:
		buy_time_left -= dt
		if buy_time_left <= 0.0:
			_broadcast_state()
	for p: Player in Net.players.values():
		p.frozen = state == State.FREEZE or state == State.ROUND_END and false
	match state:
		State.WARMUP:
			# respawn dead players during warmup
			if rules.respawn_in_warmup:
				for p: Player in Net.players.values():
					if not p.alive and p.team in [Teams.ATTACKERS, Teams.DEFENDERS] and Time.get_ticks_msec() / 1000.0 - p.death_time > 3.0:
						_spawn_player(p)
			if time_left <= 0.0:
				_start_round()
		State.FREEZE:
			if time_left <= 0.0:
				_enter_state(State.LIVE, rules.round_time)
		State.LIVE:
			if int(time_left) != int(time_left + dt) and int(time_left) in [30, 10] and time_left > 0.0:
				Net.broadcast_event("notify", {"text": "%d seconds remaining" % int(time_left), "seconds": 2.0})
			_check_elimination()
			if state == State.LIVE and time_left <= 0.0:
				_end_round(Teams.DEFENDERS, Economy.REASON_TIME)
		State.PLANTED:
			bomb_timer -= dt
			_check_elimination_planted()
			if state == State.PLANTED and bomb_timer <= 0.0:
				_bomb_explode()
		State.ROUND_END:
			if time_left <= 0.0:
				_after_round_end()
		State.HALFTIME:
			if time_left <= 0.0:
				_start_round()
		State.MATCH_END:
			pass
	# every second broadcast the timer so clients stay in sync
	if int(time_left * 2.0) != int((time_left + dt) * 2.0):
		_broadcast_state()
	# expire noise memory
	var now := Time.get_ticks_msec() / 1000.0
	noise_events = noise_events.filter(func(n): return now - n.time < 6.0)


func _start_round() -> void:
	round_number += 1
	round_kills.clear()
	bomb_planted_this_round = false
	bomb_state = "carried"
	bomb_site = ""
	bomb_planter_id = 0
	round_winner = Teams.NONE
	round_end_reason = ""
	round_mvp_id = 0
	_remove_bomb_node()
	for id in Net.entities.keys().duplicate():
		Net.server_despawn_entity(id)
	for p: Player in Net.players.values():
		p.inventory.purchases_this_round.clear()
		if p.inventory.has_slot(Inventory.SLOT_BOMB):
			p.inventory.remove(Inventory.SLOT_BOMB)
	_give_bomb_to_random_attacker()
	_spawn_all(false)
	_enter_state(State.FREEZE, rules.freeze_time)
	Events.round_started.emit(round_number)
	if overtime:
		Net.broadcast_event("notify", {"text": "Overtime round %d" % round_number, "seconds": 3.0})
	if _is_match_point():
		Net.broadcast_event("announce", {"name": "match_point"})


func _is_match_point() -> bool:
	var need := _rounds_needed_now()
	return score[Teams.ATTACKERS] == need - 1 or score[Teams.DEFENDERS] == need - 1


func _rounds_needed_now() -> int:
	if overtime:
		return rules.max_rounds / 2 + overtime_block * (rules.overtime_rounds / 2) + (rules.overtime_rounds / 2 + 1) - (rules.overtime_rounds / 2)
	return rules.rounds_to_win


func _give_bomb_to_random_attacker() -> void:
	var attackers := []
	for p: Player in Net.players.values():
		if p.team == Teams.ATTACKERS:
			attackers.append(p)
	if attackers.is_empty():
		return
	var carrier: Player = attackers[randi() % attackers.size()]
	carrier.inventory.give(WeaponDB.get_config("bomb"))
	bomb_carrier_id = carrier.peer_id
	bomb_state = "carried"
	Net.server_sync_inventory(carrier)


func _spawn_all(warmup: bool) -> void:
	var used := {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
	for p: Player in Net.players.values():
		if p.team not in [Teams.ATTACKERS, Teams.DEFENDERS]:
			p.alive = false
			continue
		_spawn_player(p, used[p.team])
		used[p.team] += 1
		if not warmup:
			var w := p.active_weapon()
			if w:
				w.on_equip()
		Net.server_sync_inventory(p)


func _spawn_player(p: Player, index: int = -1) -> void:
	var key := "attackers" if p.team == Teams.ATTACKERS else "defenders"
	var spawns: Array = layout.get("spawns", {}).get(key, [])
	var pos := Vector3(0, 1, 0)
	var yaw := 0.0
	if not spawns.is_empty():
		if index < 0:
			index = randi() % spawns.size()
		var s: Dictionary = spawns[index % spawns.size()]
		pos = Vector3(s.pos[0], s.pos[1] + 0.05, s.pos[2])
		yaw = deg_to_rad(float(s.yaw))
		# spawn validation: nudge if another alive player already stands here
		for other: Player in Net.players.values():
			if other != p and other.alive and other.global_position.distance_to(pos) < 0.8:
				pos += Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
	Net.server_spawn_player(p, pos, yaw)


func _check_elimination() -> void:
	var a := alive_count(Teams.ATTACKERS)
	var d := alive_count(Teams.DEFENDERS)
	if team_count(Teams.ATTACKERS) == 0 or team_count(Teams.DEFENDERS) == 0:
		return
	if a == 0 and d == 0:
		_end_round(Teams.DEFENDERS, Economy.REASON_ELIMINATION)
	elif a == 0:
		_end_round(Teams.DEFENDERS, Economy.REASON_ELIMINATION)
	elif d == 0:
		_end_round(Teams.ATTACKERS, Economy.REASON_ELIMINATION)


func _check_elimination_planted() -> void:
	if alive_count(Teams.DEFENDERS) == 0 and team_count(Teams.DEFENDERS) > 0:
		# bomb still explodes; attackers win by explosion once the timer runs out — speed it up
		bomb_timer = min(bomb_timer, 3.0)
	if alive_count(Teams.ATTACKERS) == 0 and alive_count(Teams.DEFENDERS) > 0:
		Events.announcer.emit("last_player") if false else null


func _end_round(winner: int, reason: String) -> void:
	if state == State.ROUND_END or state == State.MATCH_END:
		return
	round_winner = winner
	round_end_reason = reason
	score[winner] += 1
	print("[match] round %d won by %s (%s) score %d:%d" % [round_number, Teams.short_name(winner), reason, score[Teams.ATTACKERS] + (1 if winner == Teams.ATTACKERS else 0) - (1 if winner == Teams.ATTACKERS else 0), score[Teams.DEFENDERS]])
	# economy
	var loser := Teams.other(winner)
	loss_streak[winner] = economy.next_loss_streak(loss_streak[winner], true)
	loss_streak[loser] = economy.next_loss_streak(loss_streak[loser], false)
	var best_score := -1
	for p: Player in Net.players.values():
		if p.team not in [Teams.ATTACKERS, Teams.DEFENDERS]:
			continue
		var won := p.team == winner
		var reward := economy.round_end_reward(won, reason, loss_streak[p.team], p.team == Teams.ATTACKERS, bomb_planted_this_round, p.alive)
		p.money = economy.clamp_money(p.money + reward)
		if won:
			p.stats.score += 2
		var rk: int = round_kills.get(p.peer_id, 0)
		var rs := rk * 3 + (5 if (p.peer_id == bomb_planter_id and reason == Economy.REASON_BOMB_EXPLODED) else 0)
		if won and rs > best_score:
			best_score = rs
			round_mvp_id = p.peer_id
		Net.server_sync_inventory(p)
	if round_mvp_id != 0 and Net.players.has(round_mvp_id):
		Net.players[round_mvp_id].stats.mvps += 1
	for p: Player in Net.players.values():
		p.planting = false
		p.defusing = false
	_enter_state(State.ROUND_END, rules.round_end_time)
	Net._broadcast_lobby()


func _after_round_end() -> void:
	var need := rules.rounds_to_win
	var a: int = score[Teams.ATTACKERS]
	var d: int = score[Teams.DEFENDERS]
	if not overtime:
		if a >= need:
			return _end_match(Teams.ATTACKERS)
		if d >= need:
			return _end_match(Teams.DEFENDERS)
		if round_number == rules.halftime_round():
			return _halftime()
		if round_number >= rules.max_rounds:
			if a == d and rules.overtime_enabled:
				return _start_overtime()
			return _end_match(Teams.ATTACKERS if a > d else (Teams.DEFENDERS if d > a else Teams.NONE))
	else:
		var half := rules.overtime_rounds / 2
		var ot_start := rules.max_rounds + overtime_block * rules.overtime_rounds
		var rounds_in_block := round_number - ot_start
		var block_need := rules.max_rounds / 2 + overtime_block * half + half + 1
		if a >= block_need:
			return _end_match(Teams.ATTACKERS)
		if d >= block_need:
			return _end_match(Teams.DEFENDERS)
		if rounds_in_block == half:
			return _halftime()
		if rounds_in_block >= rules.overtime_rounds:
			overtime_block += 1
			Net.broadcast_event("notify", {"text": "Still tied: another overtime block", "seconds": 4.0})
			for p: Player in Net.players.values():
				p.money = economy_cfg.overtime_start_money
			return _halftime()
	_start_round()


func _halftime() -> void:
	_swap_teams()
	for p: Player in Net.players.values():
		p.money = economy_cfg.overtime_start_money if overtime else economy_cfg.start_money
		p.full_reset_inventory()
		p.alive = false
		Net.server_sync_inventory(p)
	loss_streak = {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
	_enter_state(State.HALFTIME, rules.halftime_time)
	Net.broadcast_event("notify", {"text": "Halftime — switching sides", "seconds": 5.0})
	Net._broadcast_lobby()


func _swap_teams() -> void:
	var tmp: int = score[Teams.ATTACKERS]
	score[Teams.ATTACKERS] = score[Teams.DEFENDERS]
	score[Teams.DEFENDERS] = tmp
	for id in Net.infos.keys():
		var t: int = Net.infos[id].team
		if t in [Teams.ATTACKERS, Teams.DEFENDERS]:
			var nt := Teams.other(t)
			Net.infos[id].team = nt
			var p: Player = Net.players.get(id)
			if p:
				p.team = nt
				if p.model:
					p.model.queue_free()
					p.model = null
					p.setup_visuals(id == Net.local_id)
				for pid in Net.remote_human_peers():
					Net.rpc_id(pid, "rpc_player_team", id, nt)
	swapped_at_halftime = not swapped_at_halftime


func _start_overtime() -> void:
	overtime = true
	overtime_block = 0
	for p: Player in Net.players.values():
		p.money = economy_cfg.overtime_start_money
		p.full_reset_inventory()
		Net.server_sync_inventory(p)
	loss_streak = {Teams.ATTACKERS: 0, Teams.DEFENDERS: 0}
	Net.broadcast_event("announce", {"name": "overtime"})
	Net.broadcast_event("notify", {"text": "Overtime! First to %d" % (rules.max_rounds / 2 + rules.overtime_rounds / 2 + 1), "seconds": 5.0})
	_start_round()


func _end_match(winner: int) -> void:
	match_winner = winner
	for p: Player in Net.players.values():
		p.alive = false
	_enter_state(State.MATCH_END, 0.0)
	Net.broadcast_event("announce", {"name": "attackers_win" if winner == Teams.ATTACKERS else "defenders_win"})
	Net._broadcast_lobby()


func server_return_to_lobby() -> void:
	_remove_bomb_node()
	for id in Net.entities.keys().duplicate():
		Net.server_despawn_entity(id)
	for id in Net.infos:
		Net.infos[id].ready = Net.infos[id].bot
	for p: Player in Net.players.values():
		p.alive = false
	_enter_state(State.LOBBY, 0.0)
	Net._broadcast_lobby()


func server_request_rematch(id: int) -> void:
	if state != State.MATCH_END:
		return
	rematch_votes[id] = true
	var humans := 0
	for i: Dictionary in Net.infos.values():
		if not i.bot and i.connected:
			humans += 1
	if rematch_votes.size() >= max(1, humans):
		rematch_votes.clear()
		server_start_match()
	else:
		Net.broadcast_event("notify", {"text": "Rematch votes: %d/%d" % [rematch_votes.size(), humans], "seconds": 3.0})


# ---------------------------------------------------------------------------- server: objective
func server_plant_bomb(planter: Player, site: String) -> void:
	if state != State.LIVE:
		return
	bomb_state = "planted"
	bomb_site = site
	bomb_position = planter.global_position + planter.aim_direction() * 0.6 * Vector3(1, 0, 1)
	bomb_position.y = planter.global_position.y
	bomb_timer = rules.bomb_timer
	bomb_planter_id = planter.peer_id
	bomb_planted_this_round = true
	bomb_carrier_id = 0
	planter.money = economy.clamp_money(planter.money + economy_cfg.plant_reward)
	planter.stats.score += 2
	if planter.inventory.has_bomb():
		planter.inventory.remove(Inventory.SLOT_BOMB)
		planter.switch_to_slot(planter.inventory.best_slot())
	_spawn_bomb_node()
	_enter_state(State.PLANTED, rules.bomb_timer)
	print("[match] charge planted at %s by %s (round %d)" % [site, planter.player_name, round_number])
	Net.broadcast_event("bomb_planted", {"site": site, "planter": planter.peer_id})
	Net.broadcast_event("announce", {"name": "bomb_planted"})
	server_report_noise(bomb_position, Teams.ATTACKERS, "plant")
	Net.server_sync_inventory(planter)


func server_defuse_bomb(defuser: Player) -> void:
	if state != State.PLANTED:
		return
	bomb_state = "defused"
	print("[match] charge defused by %s (round %d)" % [defuser.player_name, round_number])
	defuser.money = economy.clamp_money(defuser.money + economy_cfg.defuse_reward)
	defuser.stats.score += 3
	Net.broadcast_event("bomb_defused", {"defuser": defuser.peer_id})
	Net.broadcast_event("announce", {"name": "bomb_defused"})
	_end_round(Teams.DEFENDERS, Economy.REASON_BOMB_DEFUSED)


func _bomb_explode() -> void:
	bomb_state = "exploded"
	print("[match] charge exploded (round %d)" % round_number)
	Net.broadcast_event("bomb_exploded", {"p": bomb_position})
	# lethal radius damage
	for p: Player in Net.players.values():
		if p.alive:
			var d := p.global_position.distance_to(bomb_position)
			if d < 14.0:
				p.server_apply_damage(int(clampf(300.0 * (1.0 - d / 14.0), 0, 300)), 0, bomb_planter_id, "bomb", DamageModel.Zone.CHEST, Vector3.UP, false)
	_remove_bomb_node()
	_end_round(Teams.ATTACKERS, Economy.REASON_BOMB_EXPLODED)


func server_bomb_dropped(p: Player) -> void:
	bomb_state = "dropped"
	bomb_carrier_id = 0
	bomb_position = p.global_position
	Net.broadcast_event("bomb_dropped", {"p": p.global_position})
	_broadcast_state()


func server_bomb_picked_up(p: Player) -> void:
	bomb_state = "carried"
	bomb_carrier_id = p.peer_id
	Net.broadcast_event("bomb_picked_up", {"id": p.peer_id})
	_broadcast_state()


func _spawn_bomb_node() -> void:
	_remove_bomb_node()
	_update_bomb_node()


func _update_bomb_node() -> void:
	if bomb_state == "planted":
		if bomb_node == null and Net.world:
			bomb_node = Node3D.new()
			bomb_node.name = "PlantedBomb"
			Net.world.add_child(bomb_node)
			var mesh := WeaponMeshFactory.instantiate_weapon("bomb", false)
			if mesh:
				bomb_node.add_child(mesh)
			if DisplayServer.get_name() != "headless":
				var beep_script := load("res://src/world/BombBeeper.gd")
				var beeper: Node = beep_script.new()
				bomb_node.add_child(beeper)
		if bomb_node:
			bomb_node.global_position = bomb_position
	else:
		_remove_bomb_node()


func _remove_bomb_node() -> void:
	if bomb_node and is_instance_valid(bomb_node):
		bomb_node.queue_free()
	bomb_node = null


# ---------------------------------------------------------------------------- server: kills & economy
func server_on_kill(victim: Player, killer_id: int, weapon_id: String, headshot: bool, assist: int) -> void:
	var killer: Player = Net.players.get(killer_id)
	if killer and killer != victim:
		var team_kill := killer.team == victim.team
		var reward := economy.kill_reward(WeaponDB.get_config(weapon_id), team_kill)
		killer.money = economy.clamp_money(killer.money + reward)
		if team_kill:
			killer.stats.kills -= 1
			killer.stats.score -= 2
		else:
			killer.stats.kills += 1
			killer.stats.score += 2
			if headshot:
				killer.stats.headshots += 1
			round_kills[killer_id] = round_kills.get(killer_id, 0) + 1
		Net.server_sync_inventory(killer)
	elif killer == victim or killer_id == 0:
		victim.money = economy.clamp_money(victim.money + economy_cfg.suicide_penalty)
	if assist != 0 and Net.players.has(assist):
		Net.players[assist].stats.assists += 1
		Net.players[assist].stats.score += 1
	if victim.peer_id == bomb_carrier_id:
		pass   # drop handled by Net.server_drop_all_on_death -> server_bomb_dropped
	if state in [State.LIVE]:
		var a := alive_count(Teams.ATTACKERS)
		var d := alive_count(Teams.DEFENDERS)
		if (a == 1 and victim.team == Teams.ATTACKERS) or (d == 1 and victim.team == Teams.DEFENDERS):
			Net.broadcast_event("announce", {"name": "last_player"})
	Net._broadcast_lobby()


func server_buy(id: int, weapon_id: String) -> void:
	var p: Player = Net.players.get(id)
	if p == null or not p.alive:
		return _deny(id, "You must be alive to buy")
	if not can_buy():
		return _deny(id, "Buy time is over")
	if not in_buy_zone(p):
		return _deny(id, "You are outside the buy zone")
	# armour is handled as pseudo-items
	match weapon_id:
		"armor":
			if p.armor >= rules.max_armor:
				return _deny(id, "Armor already full")
			if p.money < economy_cfg.armor_price:
				return _deny(id, "Not enough money")
			p.money -= economy_cfg.armor_price
			p.armor = rules.max_armor
			p.inventory.purchases_this_round.append("armor")
			return _bought(p, "armor")
		"helmet":
			if p.has_helmet:
				return _deny(id, "Helmet already owned")
			var price := economy_cfg.helmet_upgrade_price if p.armor > 0 else economy_cfg.armor_price + economy_cfg.helmet_price
			if p.money < price:
				return _deny(id, "Not enough money")
			p.money -= price
			p.armor = rules.max_armor
			p.has_helmet = true
			p.inventory.purchases_this_round.append("helmet")
			return _bought(p, "helmet")
	if not NetValidation.valid_weapon_id(weapon_id):
		return _deny(id, "Unknown item")
	var cfg := WeaponDB.get_config(weapon_id)
	if cfg.id == "bomb":
		return _deny(id, "Cannot buy that")
	var team_name := "attackers" if p.team == Teams.ATTACKERS else "defenders"
	if cfg.team != "both" and cfg.team != team_name:
		return _deny(id, "Not available to your team")
	if p.money < cfg.price:
		return _deny(id, "Not enough money")
	if cfg.slot in ["primary", "secondary"]:
		var slot := Inventory.SLOT_PRIMARY if cfg.slot == "primary" else Inventory.SLOT_SECONDARY
		if p.inventory.has_slot(slot):
			var old: WeaponState = p.inventory.get_active(slot)
			if old.cfg.id == cfg.id:
				return _deny(id, "Already carrying that weapon")
			Net.server_drop_weapon(p, slot)
	if not p.inventory.give(cfg):
		return _deny(id, "Cannot carry more of that")
	p.money -= cfg.price
	p.inventory.purchases_this_round.append(cfg.id)
	var ws: WeaponState = p.inventory.find_grenade(cfg.id) if cfg.slot == "grenade" else p.inventory.get_active({"primary": 0, "secondary": 1, "melee": 2, "bomb": 4, "kit": 2}.get(cfg.slot, 2))
	if ws and cfg.slot != "grenade":
		ws.bought_this_round = true
	if cfg.slot == "primary":
		p.switch_to_slot(Inventory.SLOT_PRIMARY)
	elif cfg.slot == "secondary" and not p.inventory.has_slot(Inventory.SLOT_PRIMARY):
		p.switch_to_slot(Inventory.SLOT_SECONDARY)
	_bought(p, cfg.id)


func server_refund(id: int, weapon_id: String) -> void:
	var p: Player = Net.players.get(id)
	if p == null or not can_buy() or not in_buy_zone(p):
		return _deny(id, "Refunds only during buy time in the buy zone")
	if not p.inventory.purchases_this_round.has(weapon_id):
		return _deny(id, "Not bought this round")
	var refund := 0
	match weapon_id:
		"armor":
			refund = economy_cfg.armor_price
			p.armor = 0
		"helmet":
			refund = economy_cfg.helmet_price if p.inventory.purchases_this_round.has("armor") else economy_cfg.armor_price + economy_cfg.helmet_price
			p.has_helmet = false
			if not p.inventory.purchases_this_round.has("armor"):
				p.armor = 0
		_:
			var cfg := WeaponDB.get_config(weapon_id)
			if cfg == null:
				return _deny(id, "Unknown item")
			if cfg.slot == "kit":
				p.inventory.has_kit = false
			else:
				var ws := p.inventory.remove_by_id(weapon_id)
				if ws == null:
					return _deny(id, "You no longer carry that")
			refund = economy.refund_value(cfg)
			if p.active_slot != Inventory.SLOT_MELEE and not p.inventory.has_slot(p.active_slot):
				p.switch_to_slot(p.inventory.best_slot())
	p.inventory.purchases_this_round.erase(weapon_id)
	p.money = economy.clamp_money(p.money + refund)
	Net.server_sync_inventory(p)
	Net.send_event_to(id, "purchase_ok", {"id": "refund:" + weapon_id})


func _deny(id: int, reason: String) -> void:
	Net.send_event_to(id, "purchase_denied", {"reason": reason})


func _bought(p: Player, item: String) -> void:
	Net.server_sync_inventory(p)
	Net.send_event_to(p.peer_id, "purchase_ok", {"id": item})


# ---------------------------------------------------------------------------- server: surrender
func server_vote_surrender(id: int, yes: bool) -> void:
	if state in [State.LOBBY, State.MATCH_END, State.WARMUP] or round_number < rules.surrender_min_round:
		return Net.send_event_to(id, "notify", {"text": "Surrender is not available yet", "seconds": 3.0})
	var team: int = Net.infos[id].team if Net.infos.has(id) else Teams.NONE
	if team not in [Teams.ATTACKERS, Teams.DEFENDERS]:
		return
	if not surrender_votes.has(team):
		surrender_votes[team] = {}
		for pid in Net.infos:
			if Net.infos[pid].team == team and not Net.infos[pid].bot:
				Net.send_event_to(pid, "surrender_started", {"team": team})
	surrender_votes[team][id] = yes
	var voters := 0
	var yes_count := 0
	for pid in Net.infos:
		if Net.infos[pid].team == team and not Net.infos[pid].bot and Net.infos[pid].connected:
			voters += 1
			if surrender_votes[team].get(pid, false):
				yes_count += 1
	var needed := int(ceil(voters * rules.surrender_threshold))
	for pid in Net.infos:
		if Net.infos[pid].team == team and not Net.infos[pid].bot:
			Net.send_event_to(pid, "surrender_vote", {"team": team, "yes": yes_count, "needed": needed})
	if yes_count >= needed and voters > 0:
		Net.broadcast_event("notify", {"text": "%s surrendered" % Teams.team_name(team), "seconds": 5.0})
		round_end_reason = Economy.REASON_SURRENDER
		_end_match(Teams.other(team))


# ---------------------------------------------------------------------------- server: bot senses
func server_report_noise(pos: Vector3, team: int, kind: String) -> void:
	noise_events.append({"pos": pos, "team": team, "kind": kind, "time": Time.get_ticks_msec() / 1000.0})
	while noise_events.size() > 64:
		noise_events.pop_front()
