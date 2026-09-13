class_name MatchRules
extends Resource
## Competitive match configuration. Edit res://src/data/rules_competitive.tres or override from settings.

@export var max_rounds: int = 24
@export var rounds_to_win: int = 13
@export var overtime_enabled: bool = true
@export var overtime_rounds: int = 6
@export var round_time: float = 115.0
@export var freeze_time: float = 15.0
@export var buy_time: float = 20.0
@export var bomb_timer: float = 40.0
@export var plant_time: float = 3.2
@export var defuse_time: float = 10.0
@export var kit_defuse_time: float = 5.0
@export var round_end_time: float = 7.0
@export var halftime_time: float = 15.0
@export var warmup_time: float = 30.0
@export var max_players: int = 10
@export var team_size: int = 5
@export var friendly_fire: bool = false
@export var surrender_threshold: float = 0.8
@export var surrender_min_round: int = 3
@export var respawn_in_warmup: bool = true
@export var fall_damage_min_speed: float = 9.0
@export var fall_damage_per_speed: float = 6.0
@export var max_health: int = 100
@export var max_armor: int = 100


func validate() -> PackedStringArray:
	var e := PackedStringArray()
	if max_rounds < 2 or max_rounds % 2 != 0:
		e.append("max_rounds must be even and >= 2")
	if rounds_to_win != max_rounds / 2 + 1:
		e.append("rounds_to_win should be max_rounds/2 + 1")
	if overtime_rounds < 2 or overtime_rounds % 2 != 0:
		e.append("overtime_rounds must be even")
	if bomb_timer <= defuse_time:
		e.append("bomb_timer must exceed defuse_time")
	if team_size * 2 > max_players:
		e.append("max_players too small for team size")
	return e


func halftime_round() -> int:
	return max_rounds / 2
