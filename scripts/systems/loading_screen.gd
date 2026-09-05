extends CanvasLayer
class_name LoadingScreen

## Loading screen that shows a random image, pre-loads the game map
## in the background, then transitions to the lobby.
## The game map will be cached and load instantly when the lobby
## countdown finishes.

const LOADING_IMAGES: Array[String] = [
	"res://The Darkness Of The Grasslands assets/UI/Lobby/Game_Loading_screen-1.png",
	"res://The Darkness Of The Grasslands assets/UI/Lobby/Game_Loading_screen-2.png",
]

## Minimum display time before auto-transitioning.
const MIN_DISPLAY_TIME: float = 2.0

## How long (seconds) before the Skip button fades in.
const SKIP_FADE_DELAY: float = 5.0

## Scene to pre-load in the background.
const PRELOAD_SCENE: String = "res://scenes/game_map.tscn"

## Scene to transition to.
const RETURN_SCENE: String = "res://scenes/lobby.tscn"

## Nodes
@onready var tex_rect: TextureRect = $TextureRect
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var loading_label: Label = $LoadingLabel
@onready var skip_button: Button = $SkipButton

var _skipped: bool = false
var _load_complete: bool = false
var _load_start_time: float = 0.0
var _load_progress: float = 0.0


func _ready() -> void:
	if is_instance_valid(tex_rect):
		SubtleMotion.attach(tex_rect, SubtleMotion.Mode.BREATHE, 0.025, 0.7, 1.0)
	# SMART LOADING: if the heavy scene we would pre-load (game_map) is ALREADY
	# in the resource cache (e.g. the player played a match earlier this session),
	# there's nothing to load — so skip the loading screen entirely and go
	# straight to the lobby. Only show the loading screen when real loading is
	# actually needed.
	if ResourceLoader.has_cached(PRELOAD_SCENE):
		print("LoadingScreen: %s already pre-loaded — skipping loading screen" % PRELOAD_SCENE)
		for child: Node in get_children():
			child.visible = false
		_finish_loading()
		return

	# Pick and display a random loading image
	var chosen: String = LOADING_IMAGES[randi() % LOADING_IMAGES.size()]
	var tex: Texture2D = load(chosen)
	if tex_rect and tex:
		tex_rect.texture = tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	# Hide skip button initially (invisible + no mouse interaction)
	if skip_button:
		skip_button.modulate = Color(1, 1, 1, 0)
		skip_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skip_button.pressed.connect(_on_skip_pressed)
	
	# Start pre-loading the game map
	var err: int = ResourceLoader.load_threaded_request(PRELOAD_SCENE)
	if err != OK:
		# Threaded loading not supported (e.g. in testing), use direct load
		_load_progress = 1.0
		_load_complete = true
		_load_start_time = Time.get_ticks_msec()
	else:
		_load_start_time = Time.get_ticks_msec()
	
	# Update progress bar based on loading status
	# Timeout: if threaded load doesn't complete in 3 seconds, do direct load
	var load_timeout: float = Time.get_ticks_msec() + 3000.0
	
	while not _load_complete:
		var load_statuses: Array = []
		var load_status: int = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		var progress: float = 0.0
		
		if err == OK:
			ResourceLoader.load_threaded_get_status(PRELOAD_SCENE, load_statuses)
			load_status = load_statuses[0] if load_statuses.size() > 0 else ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
			progress = load_statuses[1] if load_statuses.size() > 1 else 0.0
		
		# Update UI
		_load_progress = progress
		if progress_bar:
			progress_bar.value = progress * 100.0
		if loading_label:
			var pct: int = int(progress * 100.0)
			loading_label.text = "Loading... %d%%" % pct
		
		var timed_out: bool = Time.get_ticks_msec() >= load_timeout
		
		if load_status == ResourceLoader.THREAD_LOAD_LOADED:
			_load_complete = true
			_load_progress = 1.0
			if progress_bar:
				progress_bar.value = 100.0
			if loading_label:
				loading_label.text = "Loading... 100%"
			break
		elif load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not timed_out:
			await get_tree().process_frame
		elif timed_out:
			# Timed out ----- do a direct load instead
			var direct: Resource = load(PRELOAD_SCENE)
			if direct:
				_load_complete = true
				_load_progress = 1.0
				if progress_bar:
					progress_bar.value = 100.0
				if loading_label:
					loading_label.text = "Loading... 100%"
			else:
				# Even direct load failed ----- proceed anyway
				_load_complete = true
				_load_progress = 1.0
			break
		else:
			# Error or unsupported ----- mark as done so we don't hang
			_load_complete = true
			_load_progress = 1.0
			if progress_bar:
				progress_bar.value = 100.0
			break
	
	# Schedule the skip button fade-in (only if loading took long enough to matter)
	var elapsed_ms: float = Time.get_ticks_msec() - _load_start_time
	if elapsed_ms < SKIP_FADE_DELAY * 1000.0:
		await get_tree().create_timer(SKIP_FADE_DELAY - elapsed_ms / 1000.0).timeout
		_show_skip_button()
	
	# Wait for minimum display time
	elapsed_ms = Time.get_ticks_msec() - _load_start_time
	if elapsed_ms < MIN_DISPLAY_TIME * 1000.0:
		await get_tree().create_timer(MIN_DISPLAY_TIME - elapsed_ms / 1000.0).timeout
	
	_finish_loading()


func _show_skip_button() -> void:
	if _skipped or not skip_button:
		return
	# Fade in the skip button over 0.5s
	var tween: Tween = create_tween()
	tween.tween_property(skip_button, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.parallel().tween_property(skip_button, "mouse_filter", Control.MOUSE_FILTER_STOP, 0.5)


func _on_skip_pressed() -> void:
	if _skipped:
		return
	_skipped = true
	
	# Fade out the skip button and progress UI
	if skip_button:
		skip_button.disabled = true
	if progress_bar:
		progress_bar.visible = false
	if loading_label:
		loading_label.text = "Loading in background..."
	
	# Go to lobby immediately ----- threaded load continues globally
	_finish_loading()


func _finish_loading() -> void:
	SceneFader.go(RETURN_SCENE, "Loading lobby...")
