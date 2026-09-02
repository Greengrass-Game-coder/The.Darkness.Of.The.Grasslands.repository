extends Node
## Comprehensive runtime tests for the EMBEDDED Dirtysweeper in arcade_room.gd.
## Unlike the tetrivo tests, these exercise the ported _dirty_* minigame logic:
## board generation invariants, reveal/flood, flag, win detection, coin awards,
## restart and close. The arcade node is built off-tree with a manual _ui so the
## DS UI build (Control construction) runs without needing a scene tree.

var _node: Node = null


func _make_node() -> Node:
	var n := Node2D.new()
	n.set_script(load("res://scripts/systems/arcade_room.gd"))
	n._ui = CanvasLayer.new()
	return n


func _setup_ds() -> void:
	_node = _make_node()
	_node._browser_active = true
	_node._menu_active = false
	_node._boot_active = false
	_node._hard_mode = false
	_node._dirty_hard = false
	GameState.is_admin = false
	GameState.tetrivo_time_penalty_until = 0
	GameState.tetrivo_last_seen_time = 0
	GameState.player_money = 0
	GameState.tetrivo_gambled = false
	GameState.tetrivo_coins_earned = 0
	GameState.tetrivo_last_coin_time = 0
	_node._start_dirtysweeper()


func test_board_generation_invariants() -> void:
	_setup_ds()
	assert(_node._dirty_active, "Dirtysweeper is active after start")
	assert(_node._dirty_board.size() == _node.DS_GRID, "board has DS_GRID rows")

	# Verify mine count and centre-cell exclusion.
	var mines := 0
	var centre: Dictionary = _node._dirty_board[_node.DS_GRID / 2][_node.DS_GRID / 2]
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if _node._dirty_board[r][c]["mine"]:
				mines += 1
	assert(mines == _node.DS_MINES, "normal board places exactly DS_MINES mines (got %d)" % mines)
	assert(not centre["mine"], "centre cell is never a mine")

	# Recompute neighbour counts independently and compare with board.
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			var expected := 0
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					var rr: int = r + dr
					var cc: int = c + dc
					if rr >= 0 and rr < _node.DS_GRID and cc >= 0 and cc < _node.DS_GRID and _node._dirty_board[rr][cc]["mine"]:
						expected += 1
			assert(_node._dirty_board[r][c]["count"] == expected,
				"count mismatch at (%d,%d): %d vs %d" % [r, c, _node._dirty_board[r][c]["count"], expected])


func test_hard_mode_mine_count() -> void:
	_setup_ds()
	_node._dirty_hard = true
	_node._dirty_new_board(Vector2i(_node.DS_GRID / 2, _node.DS_GRID / 2))
	var mines := 0
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if _node._dirty_board[r][c]["mine"]:
				mines += 1
	assert(mines == _node.DS_MINES_HARD, "hard board places DS_MINES_HARD mines (got %d)" % mines)


func test_centre_reveal_floods() -> void:
	_setup_ds()
	_node._dirty_reveal(_node.DS_GRID / 2, _node.DS_GRID / 2)
	assert(not _node._dirty_game_over, "revealing the safe centre does not end the game")
	assert(_node._dirty_board[_node.DS_GRID / 2][_node.DS_GRID / 2]["revealed"], "centre becomes revealed")


func test_reveal_mine_ends_game() -> void:
	_setup_ds()
	var mine_cell := Vector2i(-1, -1)
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if _node._dirty_board[r][c]["mine"]:
				mine_cell = Vector2i(r, c)
				break
		if mine_cell.x != -1:
			break
	assert(mine_cell.x != -1, "found a mine to reveal")
	_node._dirty_reveal(mine_cell.x, mine_cell.y)
	assert(_node._dirty_game_over, "revealing a mine sets game over")
	assert(_node._dirty_board[mine_cell.x][mine_cell.y]["revealed"], "the mine cell is revealed on loss")


func test_flag_toggle() -> void:
	_setup_ds()
	var cell := Vector2i(0, 0)
	_node._dirty_flag(cell.x, cell.y)
	assert(_node._dirty_board[cell.x][cell.y]["flagged"], "first flag marks the cell")
	_node._dirty_flag(cell.x, cell.y)
	assert(not _node._dirty_board[cell.x][cell.y]["flagged"], "second flag unmarks the cell")


func test_flagged_cell_not_revealed() -> void:
	_setup_ds()
	var cell := Vector2i(1, 1)
	_node._dirty_flag(cell.x, cell.y)
	_node._dirty_reveal(cell.x, cell.y)
	assert(not _node._dirty_board[cell.x][cell.y]["revealed"], "a flagged cell is not revealed")


func test_win_detection_and_award() -> void:
	_setup_ds()
	# Reveal every safe cell -> triggers _dirty_win().
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if not _node._dirty_board[r][c]["mine"]:
				_node._dirty_reveal(r, c)
	assert(_node._dirty_won, "revealing all safe cells wins the game")
	assert(_node._dirty_win_awarded, "win is marked as awarded")
	assert(GameState.tetrivo_coins_earned == 1, "normal win awards 1 coin (got %d)" % GameState.tetrivo_coins_earned)
	assert(GameState.player_money == 1, "normal win adds 1 money (got %d)" % GameState.player_money)


func test_hard_win_awards_two() -> void:
	_setup_ds()
	_node._dirty_hard = true
	_node._dirty_new_board(Vector2i(_node.DS_GRID / 2, _node.DS_GRID / 2))
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if not _node._dirty_board[r][c]["mine"]:
				_node._dirty_reveal(r, c)
	assert(_node._dirty_won, "hard-mode full clear wins")
	assert(GameState.tetrivo_coins_earned == 2, "hard win awards 2 coins (got %d)" % GameState.tetrivo_coins_earned)


func test_normal_win_repeatable() -> void:
	# Faithful to the ORIGINAL dirtysweeper.gd: normal-mode wins always award 1
	# coin (only the hard 2-coin bonus is daily-limited via the gambled flag).
	_setup_ds()
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if not _node._dirty_board[r][c]["mine"]:
				_node._dirty_reveal(r, c)
	var first: int = GameState.tetrivo_coins_earned
	_node._dirty_restart()
	_node._dirty_win_awarded = false
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if not _node._dirty_board[r][c]["mine"]:
				_node._dirty_reveal(r, c)
	assert(GameState.tetrivo_coins_earned == first + 1,
		"normal win is repeatable and awards 1 coin each time (%d -> %d)" % [first, GameState.tetrivo_coins_earned])


func test_hard_double_win_second_gives_one() -> void:
	# The hard 2-coin bonus is consumed by the gambled flag (daily limit);
	# a second hard win the same day awards only the base 1 coin.
	_setup_ds()
	_node._dirty_hard = true
	_node._dirty_new_board(Vector2i(_node.DS_GRID / 2, _node.DS_GRID / 2))
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if not _node._dirty_board[r][c]["mine"]:
				_node._dirty_reveal(r, c)
	assert(GameState.tetrivo_coins_earned == 2, "first hard win awards 2 coins (got %d)" % GameState.tetrivo_coins_earned)
	assert(GameState.tetrivo_gambled, "first hard win sets gambled=true")
	_node._dirty_restart()
	_node._dirty_win_awarded = false
	for r in range(_node.DS_GRID):
		for c in range(_node.DS_GRID):
			if not _node._dirty_board[r][c]["mine"]:
				_node._dirty_reveal(r, c)
	assert(GameState.tetrivo_coins_earned == 3,
		"second hard win same day awards only base 1 coin (got %d)" % GameState.tetrivo_coins_earned)


func test_restart_resets() -> void:
	_setup_ds()
	_node._dirty_reveal(_node.DS_GRID / 2, _node.DS_GRID / 2)
	_node._dirty_restart()
	assert(not _node._dirty_game_over and not _node._dirty_won, "restart resets game-over/won state")
	assert(not _node._dirty_win_awarded, "restart clears win-awarded flag")


func test_close_returns_to_browser() -> void:
	_setup_ds()
	_node._close_dirtysweeper()
	assert(not _node._dirty_active, "close deactivates Dirtysweeper")
	assert(_node._browser_active, "close returns to the minigame browser")
	assert(_node._dirty_root == null, "close frees the DS root control")
