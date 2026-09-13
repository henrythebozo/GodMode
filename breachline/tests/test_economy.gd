extends TestCase

var cfg: EconomyConfig
var eco: Economy


func _init() -> void:
	cfg = load("res://src/data/economy/economy.tres")
	eco = Economy.new(cfg)


func test_config_valid() -> void:
	assert_eq(cfg.validate().size(), 0, "economy config validates")


func test_win_rewards() -> void:
	assert_eq(eco.win_reward(Economy.REASON_ELIMINATION), 3250, "elimination")
	assert_eq(eco.win_reward(Economy.REASON_BOMB_EXPLODED), 3500, "explode")
	assert_eq(eco.win_reward(Economy.REASON_BOMB_DEFUSED), 3500, "defuse")
	assert_eq(eco.win_reward(Economy.REASON_TIME), 3250, "time")


func test_loss_bonus_progression() -> void:
	assert_eq(eco.loss_reward(1), 1400, "first loss")
	assert_eq(eco.loss_reward(2), 1900, "second loss")
	assert_eq(eco.loss_reward(5), 3400, "fifth loss")
	assert_eq(eco.loss_reward(9), 3400, "clamps at max")
	assert_eq(eco.loss_reward(0), 1400, "zero clamps low")


func test_loss_streak_updates() -> void:
	assert_eq(eco.next_loss_streak(0, false), 1)
	assert_eq(eco.next_loss_streak(3, false), 4)
	assert_eq(eco.next_loss_streak(3, true), 2, "win decays streak by one")
	assert_eq(eco.next_loss_streak(0, true), 0, "never negative")


func test_round_end_reward_variants() -> void:
	assert_eq(eco.round_end_reward(true, Economy.REASON_ELIMINATION, 0, true, false, true), 3250)
	assert_eq(eco.round_end_reward(false, Economy.REASON_ELIMINATION, 2, true, false, false), 1900, "loss bonus streak 2")
	assert_eq(eco.round_end_reward(false, Economy.REASON_BOMB_DEFUSED, 1, true, true, false), 1400 + 800, "attackers planted and lost")
	assert_eq(eco.round_end_reward(false, Economy.REASON_TIME, 1, true, false, true), 0, "attacker surviving time loss gets nothing")
	assert_eq(eco.round_end_reward(false, Economy.REASON_TIME, 1, true, false, false), 1400, "dead attacker on time loss gets loss bonus")
	assert_eq(eco.round_end_reward(false, Economy.REASON_ELIMINATION, 1, false, true, false), 1400, "defenders never get plant bonus")


func test_kill_rewards_and_clamp() -> void:
	var rifle := WeaponDB.get_config("corsair")
	var smg := WeaponDB.get_config("viper")
	var knife := WeaponDB.get_config("knife")
	assert_eq(eco.kill_reward(rifle, false), 300)
	assert_eq(eco.kill_reward(smg, false), 600)
	assert_eq(eco.kill_reward(knife, false), 1500)
	assert_eq(eco.kill_reward(rifle, true), -300, "team kill penalty")
	assert_eq(eco.kill_reward(null, false), 300, "unknown weapon default")
	assert_eq(eco.clamp_money(99999), 16000)
	assert_eq(eco.clamp_money(-50), 0)


func test_affordability_and_refund() -> void:
	assert_true(eco.can_afford(2700, 2700))
	assert_true(not eco.can_afford(2699, 2700))
	assert_eq(eco.refund_value(WeaponDB.get_config("lynx")), 3100)
