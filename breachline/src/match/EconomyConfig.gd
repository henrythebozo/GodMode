class_name EconomyConfig
extends Resource
## All money values for the round economy. Edit res://src/data/economy/economy.tres.

@export var start_money: int = 800
@export var max_money: int = 16000
@export var overtime_start_money: int = 10000
@export var win_elimination: int = 3250
@export var win_bomb_explode: int = 3500
@export var win_bomb_defuse: int = 3500
@export var win_time_expired: int = 3250
## Loss bonus per consecutive loss; index clamps to the last entry.
@export var loss_bonus: PackedInt32Array = PackedInt32Array([1400, 1900, 2400, 2900, 3400])
## Losing attackers still receive this if they planted the bomb.
@export var plant_loss_bonus: int = 800
@export var plant_reward: int = 300
@export var defuse_reward: int = 300
## Attackers that survive a round by running out the clock (bomb not planted) get nothing extra;
## defenders that survive a time-expired round still get win money.
@export var attacker_time_loss_survivor_penalty: bool = true
@export var default_kill_reward: int = 300
@export var team_kill_penalty: int = -300
@export var suicide_penalty: int = 0
## Loss streak carried over after a win: streak decreases by one instead of resetting to zero.
@export var loss_streak_decay_on_win: int = 1
@export var armor_price: int = 650
@export var helmet_price: int = 350
@export var helmet_upgrade_price: int = 350
@export var defuse_kit_price: int = 400


func validate() -> PackedStringArray:
	var e := PackedStringArray()
	if start_money < 0 or start_money > max_money:
		e.append("start_money out of range")
	if loss_bonus.is_empty():
		e.append("loss_bonus is empty")
	for i in range(1, loss_bonus.size()):
		if loss_bonus[i] < loss_bonus[i - 1]:
			e.append("loss_bonus must be non-decreasing")
	if max_money <= 0:
		e.append("max_money must be positive")
	return e
