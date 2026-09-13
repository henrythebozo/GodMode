class_name Economy
extends RefCounted
## Pure economy calculations (server authoritative; unit tested).

const REASON_ELIMINATION := "elimination"
const REASON_BOMB_EXPLODED := "bomb_exploded"
const REASON_BOMB_DEFUSED := "bomb_defused"
const REASON_TIME := "time"
const REASON_SURRENDER := "surrender"

var cfg: EconomyConfig


func _init(config: EconomyConfig) -> void:
	cfg = config


func clamp_money(m: int) -> int:
	return clampi(m, 0, cfg.max_money)


func win_reward(reason: String) -> int:
	match reason:
		REASON_ELIMINATION: return cfg.win_elimination
		REASON_BOMB_EXPLODED: return cfg.win_bomb_explode
		REASON_BOMB_DEFUSED: return cfg.win_bomb_defuse
		REASON_TIME: return cfg.win_time_expired
	return cfg.win_elimination


func loss_reward(loss_streak: int) -> int:
	var idx := clampi(loss_streak - 1, 0, cfg.loss_bonus.size() - 1)
	return cfg.loss_bonus[idx]


## Money a single player receives at round end.
## `player`: {team:int, alive:bool, won:bool, loss_streak:int(after update), planted_bomb_team:bool, survived_time_loss:bool}
func round_end_reward(won: bool, reason: String, loss_streak: int, team_is_attackers: bool, bomb_planted: bool, alive: bool) -> int:
	if won:
		return win_reward(reason)
	var reward := loss_reward(loss_streak)
	if team_is_attackers and bomb_planted:
		reward += cfg.plant_loss_bonus
	if team_is_attackers and reason == REASON_TIME and alive and cfg.attacker_time_loss_survivor_penalty:
		reward = 0   # attackers who survive by hiding until time runs out get nothing
	return reward


func next_loss_streak(previous: int, won: bool) -> int:
	if won:
		return maxi(previous - cfg.loss_streak_decay_on_win, 0)
	return previous + 1


func kill_reward(weapon: WeaponConfig, team_kill: bool) -> int:
	if team_kill:
		return cfg.team_kill_penalty
	if weapon == null:
		return cfg.default_kill_reward
	return weapon.kill_reward


func can_afford(money: int, price: int) -> bool:
	return money >= price


func refund_value(weapon: WeaponConfig) -> int:
	return weapon.price
