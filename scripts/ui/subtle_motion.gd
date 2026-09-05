class_name SubtleMotion
extends Node

## Reusable subtle looping motion for static sprites / UI nodes.
##
## Add this as a CHILD of the node you want to animate (or call the static
## SubtleMotion.attach(...) helper). It gently animates its PARENT's
## position / rotation / scale / modulate. Works on both Node2D and Control.
##
## Intensity is driven globally by GameState.motion_intensity (0..1), so the
## player can dial the whole game's subtle motion up/down or turn it off.
## All modes settle back to the parent's base transform at intensity 0.

enum Mode { BOB, SWAY, PULSE, FLY, BREATHE }

## What kind of idle motion to apply.
@export var mode: Mode = Mode.PULSE
## Motion strength. For BOB/FLY this is in pixels, for SWAY/PULSE it is a
## rotation/scale factor, for BREATHE it is an alpha factor.
@export var amplitude: float = 0.03
## How fast the motion loops (radians of the driving sine per second).
@export var speed: float = 1.5
## Starting offset of the sine wave, to desync multiple nodes.
@export var phase: float = 0.0

var _t: float = 0.0
var _base_pos: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_rot: float = 0.0
var _base_mod: Color = Color.WHITE


static func attach(target: Node, mode: Mode, amplitude: float = 0.03, speed: float = 1.5, phase: float = 0.0) -> SubtleMotion:
	## Convenience: create a SubtleMotion child on `target` that animates it.
	var sm := SubtleMotion.new()
	sm.mode = mode
	sm.amplitude = amplitude
	sm.speed = speed
	sm.phase = phase
	target.add_child(sm)
	return sm


func _ready() -> void:
	_t = phase
	var target := get_parent()
	if target == null:
		return
	if "position" in target:
		_base_pos = target.get("position")
	if "scale" in target:
		_base_scale = target.get("scale")
	if "rotation" in target:
		_base_rot = target.get("rotation")
	if "modulate" in target:
		_base_mod = target.get("modulate")


func _process(delta: float) -> void:
	var target := get_parent()
	if target == null:
		return
	var intensity: float = 1.0
	if GameState != null:
		var v = GameState.get("motion_intensity")
		if v != null:
			intensity = clampf(float(v), 0.0, 1.0)
	_t += delta * speed
	match mode:
		Mode.BOB:
			if "position" in target:
				target.set("position", Vector2(_base_pos.x, _base_pos.y + sin(_t) * amplitude * intensity))
		Mode.SWAY:
			if "rotation" in target:
				target.set("rotation", _base_rot + sin(_t) * (amplitude * intensity))
		Mode.PULSE:
			if "scale" in target:
				var s: float = 1.0 + sin(_t) * (amplitude * intensity)
				target.set("scale", _base_scale * s)
		Mode.FLY:
			if "position" in target:
				target.set("position", Vector2(
					_base_pos.x + sin(_t * 0.6) * amplitude * intensity,
					_base_pos.y + sin(_t) * amplitude * intensity
				))
			if "rotation" in target:
				target.set("rotation", _base_rot + sin(_t * 0.5) * (amplitude * 0.5 * intensity))
		Mode.BREATHE:
			if "modulate" in target:
				var a: float = _base_mod.a * (1.0 - 0.04 * intensity + abs(sin(_t)) * 0.04 * intensity)
				target.set("modulate", Color(_base_mod.r, _base_mod.g, _base_mod.b, a))
