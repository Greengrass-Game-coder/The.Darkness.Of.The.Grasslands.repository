class_name AIDifficultyController
extends Node
## Dynamic AI difficulty system that scales bot behavior based on
## match progress, survivor count, and player performance.
##
## Attach to any AI bot to make it progressively harder as the match goes on.
##
## Scaling dimensions:
##   - Time remaining: speed, aggression, prediction accuracy
##   - Survivor count: fewer survivors = more aggressive pursuit
##   - Player HP: low HP = bot "smells blood" (faster, more relentless)
##   - Teleport usage: intelligent teleport positioning near puzzles

# ── Difficulty Parameters ──

## How fast the difficulty scales (higher = faster ramp)
@export var scaling_rate: float = 1.0

## Sprint speed at min difficulty (match start, full survivors)
@export var base_sprint_speed: float = 350.0

## Maximum sprint speed at max difficulty
@export var max_sprint_speed: float = 600.0

## Hit cooldown at min difficulty
@export var base_hit_cd: float = 2.5

## Minimum hit cooldown at max difficulty
@export var min_hit_cd: float = 1.0

## Teleport cooldown at max difficulty  
@export var base_teleport_cd: float = 12.0
@export var min_teleport_cd: float = 6.0

## Reaction delay range (higher difficulty = faster reactions)
@export var reaction_min_easy: float = 0.3
@export var reaction_max_easy: float = 0.6
@export var reaction_min_hard: float = 0.05
@export var reaction_max_hard: float = 0.2

## Block prediction accuracy (0.0 = random, 1.0 = perfect)
@export var block_prediction_easy: float = 0.3
@export var block_prediction_hard: float = 0.85

# ── State ──
var _difficulty: float = 0.0  # 0.0 (easiest) → 1.0 (hardest)
var _bot: Node2D = null
var _time_remaining: float = 240.0
var _survivor_count: int = 4
var _bot_target_hp: float = 100.0


func initialize(bot: Node2D) -> void:
	_bot = bot


func update_difficulty(time_remaining: float, survivor_count: int, target_hp: float) -> void:
	"""Call every frame with current match state to recalculate AI parameters."""
	_time_remaining = time_remaining
	_survivor_count = max(survivor_count, 1)
	_bot_target_hp = target_hp

	# Calculate difficulty from 3 axes:
	# 1. Time pressure: 0.0 at 240s+, 1.0 at 0s (clamped so extra time doesn't reduce difficulty)
	var time_factor: float = clampf(1.0 - (time_remaining / 240.0), 0.0, 1.0)

	# 2. Survivor count: more aggressive when fewer survivors remain
	var survivor_factor: float = 1.0 - (float(survivor_count) / 4.0)

	# 3. Target HP: smell blood when target is injured
	var hp_factor: float = 1.0 - clampf(target_hp / 100.0, 0.0, 1.0)

	# Weighted blend (time is primary, survivors secondary, HP tertiary)
	_difficulty = clampf(
		(time_factor * 0.6 + survivor_factor * 0.25 + hp_factor * 0.15) * scaling_rate,
		0.0, 1.0
	)

	_apply_to_bot()


func _apply_to_bot() -> void:
	if not is_instance_valid(_bot):
		return

	# Sprint speed
	var speed: float = lerpf(base_sprint_speed, max_sprint_speed, _difficulty)
	if "sprint_speed" in _bot:
		_bot.sprint_speed = speed

	# Hit cooldown
	var hit_cd: float = lerpf(base_hit_cd, min_hit_cd, _difficulty)
	if "hit_cooldown" in _bot:
		_bot.hit_cooldown = hit_cd

	# Reaction delay
	if "reaction_delay_min" in _bot:
		_bot.reaction_delay_min = lerpf(reaction_min_easy, reaction_min_hard, _difficulty)
	if "reaction_delay_max" in _bot:
		_bot.reaction_delay_max = lerpf(reaction_max_easy, reaction_max_hard, _difficulty)

	# Block prediction accuracy
	if "block_feint_chance" in _bot:
		_bot.block_feint_chance = lerpf(block_prediction_easy, block_prediction_hard, _difficulty)


func get_difficulty() -> float:
	return _difficulty


func get_difficulty_label() -> String:
	if _difficulty < 0.2:
		return "Easy"
	elif _difficulty < 0.4:
		return "Normal"
	elif _difficulty < 0.6:
		return "Hard"
	elif _difficulty < 0.8:
		return "Very Hard"
	else:
		return "Nightmare"
