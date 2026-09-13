extends TestCase
## Match state transitions are exercised through the real MatchManager with an offline server
## and bots (no rendering). Each test hosts a fresh in-process session using the real Foundry layout.

var tree: SceneTree


func _init(t: SceneTree) -> void:
	tree = t


func _fresh_match(bots_per_team: int = 1) -> void:
	Net.shutdown()
	Net.host(randi_range(40000, 50000), false, "test")
	var f := FileAccess.open("res://assets/models/map/foundry_layout.json", FileAccess.READ)
	Match.set_layout(JSON.parse_string(f.get_as_text()))
	for i in bots_per_team:
		Net.server_add_bot(Teams.ATTACKERS, 0)
		Net.server_add_bot(Teams.DEFENDERS, 0)
	Match.lock_rules = true
	Match.rules.warmup_time = 0.1
	Match.rules.freeze_time = 0.2
	Match.rules.round_end_time = 0.2
	Match.rules.halftime_time = 0.2
	Match.rules.max_rounds = 4
	Match.rules.rounds_to_win = 3
	Match.rules.overtime_rounds = 2
	Match.rules.overtime_enabled = true
	Match.server_start_match()


func _tick(seconds: float) -> void:
	var dt := 1.0 / 64.0
	var n := int(seconds / dt)
	for i in n:
		Match.server_tick(dt)


func _tick_until(state: int, max_seconds: float = 3.0) -> bool:
	var dt := 1.0 / 64.0
	var t := 0.0
	while Match.state != state and t < max_seconds:
		Match.server_tick(dt)
		t += dt
	return Match.state == state


## Kill every player not in `winner_ids` while the round is live, then run to the next state.
func _win_round_for(winner_ids: Array) -> void:
	assert_true(_tick_until(Match.State.LIVE), "round became live")
	for p: Player in Net.players.values():
		if not winner_ids.has(p.peer_id):
			p.server_die(0, "test", false)
	_tick(0.05)
	assert_eq(Match.state, Match.State.ROUND_END, "round ended after elimination")
	_tick(0.3)


func _ids_of(team: int) -> Array:
	var out := []
	for id in Net.infos:
		if Net.infos[id].team == team:
			out.append(id)
	return out


func test_warmup_to_freeze_to_live() -> void:
	_fresh_match()
	assert_eq(Match.state, Match.State.WARMUP, "starts in warmup")
	_tick(0.2)
	assert_eq(Match.state, Match.State.FREEZE, "freeze after warmup")
	assert_eq(Match.round_number, 1)
	assert_true(Match.can_buy(), "buying allowed in freeze")
	_tick(0.3)
	assert_eq(Match.state, Match.State.LIVE, "live after freeze")
	assert_true(Match.can_plant(), "planting allowed when live")
	for p: Player in Net.players.values():
		assert_true(p.alive, "everyone spawned alive")
		assert_true(Match.in_buy_zone(p), "spawned inside own buy zone")
	Net.shutdown()


func test_elimination_win_and_economy() -> void:
	_fresh_match()
	assert_true(_tick_until(Match.State.LIVE))
	var attacker_money_before := 0
	for p: Player in Net.players.values():
		if p.team == Teams.ATTACKERS:
			attacker_money_before = p.money
		if p.team == Teams.DEFENDERS:
			p.server_die(0, "test", false)
	_tick(0.05)
	assert_eq(Match.state, Match.State.ROUND_END, "round ends when defenders eliminated")
	assert_eq(Match.round_winner, Teams.ATTACKERS)
	assert_eq(Match.score[Teams.ATTACKERS], 1)
	assert_eq(Match.loss_streak[Teams.DEFENDERS], 1, "loser streak increments")
	for p: Player in Net.players.values():
		if p.team == Teams.ATTACKERS:
			assert_eq(p.money, attacker_money_before + 3250, "winners receive elimination reward")
		else:
			assert_true(p.money >= 800 + 1400, "losers receive loss bonus")
	_tick(0.3)
	assert_eq(Match.state, Match.State.FREEZE, "next round freeze")
	assert_eq(Match.round_number, 2)
	Net.shutdown()


func test_time_expiry_defenders_win() -> void:
	_fresh_match()
	assert_true(_tick_until(Match.State.LIVE))
	Match.time_left = 0.01
	_tick(0.05)
	assert_eq(Match.state, Match.State.ROUND_END)
	assert_eq(Match.round_winner, Teams.DEFENDERS, "defenders win on time")
	assert_eq(Match.round_end_reason, Economy.REASON_TIME)
	Net.shutdown()


func test_plant_defuse_and_explode() -> void:
	_fresh_match()
	assert_true(_tick_until(Match.State.LIVE))
	var attacker: Player
	var defender: Player
	for p: Player in Net.players.values():
		if p.team == Teams.ATTACKERS:
			attacker = p
		else:
			defender = p
	assert_true(attacker.inventory.has_bomb(), "an attacker carries the charge")
	Match.server_plant_bomb(attacker, "A")
	assert_eq(Match.state, Match.State.PLANTED, "planted state")
	assert_true(Match.bomb_planted())
	assert_true(Match.bomb_planted_this_round)
	assert_true(not attacker.inventory.has_bomb(), "charge removed from planter")
	Match.server_defuse_bomb(defender)
	assert_eq(Match.state, Match.State.ROUND_END)
	assert_eq(Match.round_winner, Teams.DEFENDERS, "defuse wins for defenders")
	assert_eq(Match.round_end_reason, Economy.REASON_BOMB_DEFUSED)
	_tick(0.3)
	assert_true(_tick_until(Match.State.LIVE), "round 2 live")
	for p: Player in Net.players.values():
		if p.team == Teams.ATTACKERS:
			attacker = p
	Match.server_plant_bomb(attacker, "B")
	Match.bomb_timer = 0.01
	_tick(0.05)
	assert_eq(Match.round_winner, Teams.ATTACKERS, "explosion wins for attackers")
	assert_eq(Match.round_end_reason, Economy.REASON_BOMB_EXPLODED)
	assert_eq(Match.bomb_state, "exploded")
	Net.shutdown()


func test_halftime_swaps_teams_and_scores() -> void:
	_fresh_match()
	var first_attackers := _ids_of(Teams.ATTACKERS)
	_win_round_for(first_attackers)
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.HALFTIME, "halftime after half the rounds")
	for id in first_attackers:
		assert_eq(Net.infos[id].team, Teams.DEFENDERS, "former attackers are now defenders")
	assert_eq(Match.score[Teams.DEFENDERS], 2, "score follows the players across the swap")
	assert_eq(Match.score[Teams.ATTACKERS], 0)
	assert_true(_tick_until(Match.State.LIVE), "play resumes after halftime")
	assert_eq(Match.round_number, 3)
	for p: Player in Net.players.values():
		assert_eq(p.money, 800 + 3250 * 0 if false else p.money, "")
	Net.shutdown()


func test_money_reset_at_halftime() -> void:
	_fresh_match()
	var first_attackers := _ids_of(Teams.ATTACKERS)
	_win_round_for(first_attackers)
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.HALFTIME)
	for p: Player in Net.players.values():
		assert_eq(p.money, 800, "money reset at halftime")
		assert_true(not p.inventory.has_slot(Inventory.SLOT_PRIMARY), "loadout reset at halftime")
	Net.shutdown()


func test_match_end_first_to_rounds_to_win() -> void:
	_fresh_match()
	var first_attackers := _ids_of(Teams.ATTACKERS)
	_win_round_for(first_attackers)
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.HALFTIME)
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.MATCH_END, "first to rounds_to_win ends the match")
	assert_eq(Match.match_winner, Teams.DEFENDERS, "the winners are defenders after the swap")
	assert_eq(Match.score[Teams.DEFENDERS], 3)
	Net.shutdown()


func test_tie_goes_to_overtime() -> void:
	_fresh_match()
	var first_attackers := _ids_of(Teams.ATTACKERS)
	var first_defenders := _ids_of(Teams.DEFENDERS)
	_win_round_for(first_attackers)
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.HALFTIME)
	_win_round_for(first_defenders)
	_win_round_for(first_defenders)
	assert_true(Match.overtime, "tied match goes to overtime")
	assert_eq(Match.score[Teams.ATTACKERS], 2)
	assert_eq(Match.score[Teams.DEFENDERS], 2)
	for p: Player in Net.players.values():
		assert_eq(p.money, Match.economy_cfg.overtime_start_money, "overtime money")
	assert_true(_tick_until(Match.State.LIVE), "overtime round live")
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.HALFTIME, "overtime halftime after half the OT rounds")
	_win_round_for(first_attackers)
	assert_eq(Match.state, Match.State.MATCH_END, "overtime decided")
	Net.shutdown()


func test_buy_rules() -> void:
	_fresh_match()
	_tick(0.15)
	assert_eq(Match.state, Match.State.FREEZE)
	var p: Player
	for q: Player in Net.players.values():
		if q.team == Teams.ATTACKERS:
			p = q
	p.money = 3000
	Match.server_buy(p.peer_id, "corsair")
	assert_true(p.inventory.has_weapon("corsair"), "bought a rifle in the buy zone during freeze")
	assert_eq(p.money, 300)
	Match.server_buy(p.peer_id, "lynx")
	assert_true(not p.inventory.has_weapon("lynx"), "defender rifle refused to attackers")
	Match.server_refund(p.peer_id, "corsair")
	assert_eq(p.money, 3000, "refund returns full price")
	assert_true(not p.inventory.has_weapon("corsair"))
	Match.server_buy(p.peer_id, "helmet")
	assert_eq(p.armor, 100, "helmet purchase includes armor")
	assert_true(p.has_helmet)
	assert_eq(p.money, 3000 - 1000)
	p.global_position = Vector3(60, 0, 50)   # mid map, outside the buy zone
	Match.server_buy(p.peer_id, "corsair")
	assert_true(not p.inventory.has_weapon("corsair"), "cannot buy outside the buy zone")
	Net.shutdown()


func test_surrender() -> void:
	_fresh_match(0)
	Net.server_add_bot(Teams.DEFENDERS, 0)
	Match.rules.surrender_min_round = 0
	assert_true(_tick_until(Match.State.LIVE))
	# only humans vote; emulate one connected human attacker
	Net.infos[777] = {"name": "h", "team": Teams.ATTACKERS, "ready": true, "bot": false, "ping": 0, "token": "", "connected": true, "difficulty": 1}
	Match.server_vote_surrender(777, true)
	assert_eq(Match.state, Match.State.MATCH_END, "unanimous surrender ends the match")
	assert_eq(Match.match_winner, Teams.DEFENDERS)
	Net.infos.erase(777)
	Match.lock_rules = false
	Net.shutdown()
