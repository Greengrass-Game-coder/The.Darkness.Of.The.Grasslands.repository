class_name CutscenePlayer
extends CanvasLayer

## Plays a PNG sequence as a cinematic cutscene overlay.
## Loads all frames from a folder, animates at configurable FPS,
## optionally plays audio alongside. Emits finished when done.

signal finished()

@export var fps: float = 10.0  # Frames per second
# If > 0, fade the cutscene in from black over this many seconds at the start.
@export var fade_in_duration: float = 0.0
# If true, when all frames have played the cutscene stays frozen on the LAST
# frame (no fade-out, no hiding) and emits finished — used by the killer outro.
@export var hold_on_last_frame: bool = false

var _frames: Array[Texture2D] = []
var _current_frame: int = 0
var _playing: bool = false
var _sprite: Sprite2D = null
var _black_bg: ColorRect = null
var _fade_overlay: ColorRect = null
var _timer: float = 0.0
var _total_duration: float = 0.0
var _is_fading_out: bool = false
var _audio_player: AudioStreamPlayer = null


func play_cutscene(folder_path: String, audio_path: String = "") -> void:
	"""Load all PNGs from folder and play them as a cutscene."""
	# Load frames
	_frames.clear()
	var frame_idx: int = 0
	while true:
		var path: String = folder_path.path_join("frame_%05d.png" % frame_idx)
		if not ResourceLoader.exists(path):
			# Try alternate pattern: frame_00000.png (5 digits) ----- already using this
			# If not found, stop loading
			if frame_idx == 0:
				push_error("CutscenePlayer: No frames found in ", folder_path)
				finished.emit()
				return
			break
		var tex: Texture2D = load(path)
		if tex:
			_frames.append(tex)
		frame_idx += 1
	
	print("CutscenePlayer: Loaded ", _frames.size(), " frames from ", folder_path)
	
	if _frames.is_empty():
		push_error("CutscenePlayer: No frames loaded")
		finished.emit()
		return
	
	_build_ui()
	
	# Load audio if provided
	if not audio_path.is_empty() and ResourceLoader.exists(audio_path):
		_audio_player = AudioStreamPlayer.new()
		_audio_player.stream = load(audio_path)
		_audio_player.autoplay = false
		_audio_player.bus = &"Master"
		_audio_player.finished.connect(_on_audio_finished)
		add_child(_audio_player)
	
	_current_frame = 0
	_playing = true
	_timer = 0.0
	_total_duration = float(_frames.size()) / fps
	_is_fading_out = false
	show()
	
	# Fade the cutscene in from black if requested (default: no fade → pops in).
	if fade_in_duration > 0.0 and is_instance_valid(_fade_overlay):
		_fade_overlay.color = Color(0, 0, 0, 1)
		var fade_in: Tween = create_tween()
		fade_in.tween_property(_fade_overlay, "color", Color(0, 0, 0, 0), fade_in_duration)
	
	# Play audio
	if _audio_player:
		_audio_player.play()


func _build_ui() -> void:
	"""Create the cutscene display elements."""
	# Full-screen container
	var container := Control.new()
	container.name = "CutsceneContainer"
	container.anchors_preset = Control.PRESET_FULL_RECT
	add_child(container)
	
	# Black background (fills gaps if frames don't cover full screen)
	_black_bg = ColorRect.new()
	_black_bg.name = "CutsceneBg"
	_black_bg.color = Color(0, 0, 0, 1)
	_black_bg.anchors_preset = Control.PRESET_FULL_RECT
	container.add_child(_black_bg)
	
	# Sprite to display frames (centered on screen at full resolution)
	_sprite = Sprite2D.new()
	_sprite.name = "CutsceneSprite"
	_sprite.centered = true
	# 1280x720 frames displayed at viewport scale
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1024, 768)
	var tex_size: Vector2 = _frames[0].get_size() if not _frames.is_empty() else Vector2(1280, 720)
	
	_sprite.position = viewport_size * 0.5
	
	# Scale to fit viewport
	var scale_x: float = viewport_size.x / tex_size.x
	var scale_y: float = viewport_size.y / tex_size.y
	var fit_scale: float = min(scale_x, scale_y)
	_sprite.scale = Vector2(fit_scale, fit_scale)
	
	_sprite.texture = _frames[0]
	container.add_child(_sprite)
	
	# Fade overlay on top (for the 1-second-before-end fade-out)
	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "FadeOverlay"
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.anchors_preset = Control.PRESET_FULL_RECT
	container.add_child(_fade_overlay)


func _process(delta: float) -> void:
	if not _playing:
		return
	
	_timer += delta
	
	# Auto-fade to black when 1 second remains (skipped in hold-on-last-frame mode)
	if not hold_on_last_frame and not _is_fading_out and _total_duration > 0 and _timer >= _total_duration - 1.0:
		_is_fading_out = true
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(_fade_overlay, "color", Color(0, 0, 0, 1), 1.0)
	
	var frame_duration: float = 1.0 / fps
	while _timer >= frame_duration and _playing:
		_timer -= frame_duration
		_current_frame += 1
		
		if _current_frame >= _frames.size():
			_playing = false
			if hold_on_last_frame:
				# Freeze on the final frame: keep the last texture visible and
				# report finished so the caller can overlay content on it.
				_current_frame = _frames.size() - 1
				_sprite.texture = _frames[_current_frame]
			_on_cutscene_done()
			return
		
		_sprite.texture = _frames[_current_frame]


func _on_cutscene_done() -> void:
	"""Called when all frames have played."""
	finished.emit()
	# Don't queue_free here ----- let the caller handle cleanup
	# in case they want to fade out or something


func fade_out_and_free(duration: float = 0.5) -> void:
	"""Fade the cutscene to black, then free it.
	CanvasLayer has no modulate, so we fade the black bg overlay instead."""
	if not _black_bg:
		queue_free()
		return
	_playing = false
	var tween: Tween = create_tween()
	tween.tween_property(_black_bg, "color", Color(0, 0, 0, 1), duration)
	await tween.finished
	queue_free()


# Skip functionality removed — killer intro is mandatory viewing.


func _on_audio_finished() -> void:
	"""Audio finished ----- do nothing special, cutscene continues."""
	pass
