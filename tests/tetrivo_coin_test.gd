extends Node
## Tests for the Tetrivo coin-reward logic (arcade_room.gd).
## Uses the real project autoloads (GameState, AuthManager).

var _node: Node = null

func _make_node() -> Node:
	var n := Node2D.new()
	n.set_script(load("res://scripts/systems/arcade_room.gd"))
	return n  # not in the tree, so _ready() won't build the room

func _setup() -> void:
	_node = _make_node()
	GameState.is_admin = false
	GameState.tetrivo_time_penalty_until = 0
	GameState.tetrivo_last_seen_time = 0
	GameState.player_money = 0
	GameState.tetrivo_gambled = false

func test_first_win_awards_one() -> void:
	_setup()
	GameState.tetrivo_coins_earned = 0
	GameState.tetrivo_last_coin_time = 0
	_node._hard_mode = false
	var a: int = _node._resolve_win_reward()
	assert(a == 1 and GameState.tetrivo_coins_earned == 1 and GameState.player_money == 1,
		"first win should award 1 coin")

func test_same_day_second_win_farmable() -> void:
	# Per the documented design, NORMAL wins are intentionally farmable (1 coin,
	# no daily gate). Only the hard-mode 2-coin bonus is daily-limited.
	_setup()
	GameState.tetrivo_coins_earned = 1
	GameState.tetrivo_last_coin_time = _node._now_sec()
	_node._hard_mode = false
	var a: int = _node._resolve_win_reward()
	assert(a == 1 and GameState.tetrivo_coins_earned == 2,
		"same-day second normal win should still award 1 coin (farmable)")

func test_next_day_second_win() -> void:
	_setup()
	GameState.tetrivo_coins_earned = 1
	GameState.tetrivo_last_coin_time = _node._now_sec() - 86400
	_node._hard_mode = false
	var a: int = _node._resolve_win_reward()
	assert(a == 1 and GameState.tetrivo_coins_earned == 2,
		"next-day second normal win should reach 2 coins")

func test_gamble_win_reaches_three() -> void:
	_setup()
	GameState.tetrivo_coins_earned = 1
	GameState.tetrivo_last_coin_time = _node._now_sec() - 86400
	_node._hard_mode = true
	var a: int = _node._resolve_win_reward()
	assert(a == 2 and GameState.tetrivo_coins_earned == 3 and GameState.tetrivo_gambled,
		"hard-mode gamble win should reach 3 coins and mark gambled")

func test_gamble_loss_keeps_one() -> void:
	_setup()
	GameState.tetrivo_coins_earned = 1
	_node._on_gamble_lost()
	assert(GameState.tetrivo_coins_earned == 1 and GameState.tetrivo_gambled,
		"gamble loss should keep 1 coin and lock further earning")

func test_time_tamper_penalty() -> void:
	_setup()
	GameState.tetrivo_last_seen_time = _node._now_sec() + 200
	GameState.tetrivo_last_coin_time = _node._now_sec() + 100
	_node._detect_time_tamper(_node._now_sec())
	assert(GameState.tetrivo_time_penalty_until > _node._now_sec(),
		"clock roll-back should add a +5h penalty")

func test_admin_unlimited() -> void:
	_setup()
	GameState.is_admin = true
	GameState.tetrivo_coins_earned = 1
	GameState.tetrivo_last_coin_time = _node._now_sec()  # same day
	_node._hard_mode = false
	var a: int = _node._resolve_win_reward()
	assert(a == 1 and GameState.tetrivo_coins_earned == 2,
		"admin should earn despite the same-day limit")
