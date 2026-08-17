extends Node
## Professional sound system — wraps SFXManager with positional audio,
## audio bus management, volume persistence, and ambient sound support.
##
## Use as autoload: register as "SoundManager" in Project Settings.
## Falls back gracefully: if not registered as autoload, SFXManager
## is called directly.

# ── Audio Buses ──
const BUS_MASTER: int = 0
const BUS_MUSIC: int = 1
const BUS_SFX: int = 2

var _music_player: AudioStreamPlayer = null
var _ambient_player: AudioStreamPlayer = null


func _ready() -> void:
	_apply_saved_volumes()


# ═══════════════ MUSIC ═══════════════

func play_music(stream: AudioStream, loop: bool = true, volume_db: float = 0.0) -> void:
	if not _music_player:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		_music_player.bus = &"Music"
		add_child(_music_player)

	var old: float = _music_player.volume_db if _music_player.playing else -80.0

	_music_player.stream = stream
	_music_player.volume_db = old

	var tween := create_tween()
	if _music_player.playing:
		# Crossfade: fade out old, swap, fade in new
		var old_player := _music_player
		tween.tween_property(old_player, "volume_db", -80.0, 0.5)
		await tween.finished
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		_music_player.bus = &"Music"
		_music_player.stream = stream
		_music_player.volume_db = -80.0
		_music_player.play()
		add_child(_music_player)
		old_player.stop()
		old_player.queue_free()

		var ft := create_tween()
		ft.tween_property(_music_player, "volume_db", volume_db, 0.5)
		if loop:
			if stream is AudioStreamWAV:
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			_music_player.finished.connect(func(): if _music_player: _music_player.play())
	else:
		tween.tween_property(_music_player, "volume_db", volume_db, 0.5)
		_music_player.play()
		if loop:
			if stream is AudioStreamWAV:
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			_music_player.finished.connect(func(): if _music_player: _music_player.play())


func stop_music(duration: float = 0.5) -> void:
	if not _music_player:
		return
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -80.0, duration)
	await tween.finished
	if is_instance_valid(_music_player):
		_music_player.stop()


func set_music_volume(linear: float) -> void:
	if _music_player:
		_music_player.volume_db = linear_to_db(clampf(linear, 0.0, 1.0))


# ═══════════════ POSITIONAL SFX ═══════════════

func play_positional(sound_path: String, position: Vector2, max_distance: float = 800.0, volume_db: float = 0.0) -> void:
	"""Play a positional 2D sound — audible based on listener distance."""
	var player := AudioStreamPlayer2D.new()
	if ResourceLoader.exists(sound_path):
		player.stream = load(sound_path)
	else:
		push_warning("SoundManager: Sound not found: ", sound_path)
		player.queue_free()
		return
	player.global_position = position
	player.max_distance = max_distance
	player.volume_db = volume_db
	player.bus = &"SFX"
	add_child(player)
	player.play()

	# Auto-cleanup
	get_tree().create_timer(max(player.stream.get_length(), 0.5) + 0.5).timeout.connect(
		func(): if is_instance_valid(player): player.queue_free()
	)


func play_sfx(sfx_name: String) -> void:
	"""Delegate to SFXManager or play directly."""
	var sm := get_node_or_null("/root/SFXManager")
	if sm and sm.has_method("play_sfx"):
		sm.play_sfx(sfx_name)
	else:
		_synth_beep(440.0, 0.1, 0.3)


# ═══════════════ SYNTH BACKUP ═══════════════

func _synth_beep(freq: float, duration: float, volume: float) -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = max(duration, 0.5)

	var player := AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = linear_to_db(volume)
	player.bus = &"SFX"
	add_child(player)
	player.play()

	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if not playback:
		return

	var frames: int = int(44100.0 * duration)
	var inc: float = freq / 44100.0
	var phase: float = 0.0
	for _i in frames:
		var s: float = sin(phase * TAU) * 0.3
		playback.push_frame(Vector2(s, s))
		phase += inc

	while playback.get_frames_available() > 0:
		playback.push_frame(Vector2.ZERO)

	get_tree().create_timer(duration + 0.1).timeout.connect(
		func(): if is_instance_valid(player): player.queue_free()
	)


# ═══════════════ AMBIENT ═══════════════

func play_ambient(sound_path: String, volume_db: float = -12.0) -> void:
	if not _ambient_player:
		_ambient_player = AudioStreamPlayer.new()
		_ambient_player.name = "AmbientPlayer"
		_ambient_player.bus = &"SFX"
		add_child(_ambient_player)

	if not ResourceLoader.exists(sound_path):
		return

	_ambient_player.stream = load(sound_path)
	if _ambient_player.stream is AudioStreamWAV:
		(_ambient_player.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_ambient_player.volume_db = volume_db
	_ambient_player.play()
	_ambient_player.finished.connect(func(): if _ambient_player: _ambient_player.play())


func stop_ambient() -> void:
	if _ambient_player:
		_ambient_player.stop()


# ═══════════════ VOLUME PERSISTENCE ═══════════════

func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = linear_to_db(clampf(linear, 0.0, 1.0))
	AudioServer.set_bus_volume_db(idx, db)

	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has("logged_in_username") and gs.logged_in_username != "":
		var sm := get_node_or_null("/root/SaveManager")
		if sm:
			var data: Dictionary = sm.load_player_data(gs.logged_in_username)
			data["bus_vol_" + bus_name] = db
			sm.save_player_data(gs.logged_in_username, data)


func get_bus_volume(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _apply_saved_volumes() -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs or gs.logged_in_username.is_empty():
		return
	var sm := get_node_or_null("/root/SaveManager")
	if not sm:
		return
	var data: Dictionary = sm.load_player_data(gs.logged_in_username)
	for bus_name in ["Master", "Music", "SFX"]:
		var key: String = "bus_vol_" + bus_name
		if data.has(key):
			var idx: int = AudioServer.get_bus_index(bus_name)
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, data[key])
		var mute_key: String = "bus_mute_" + bus_name
		if data.has(mute_key):
			var idx: int = AudioServer.get_bus_index(bus_name)
			if idx >= 0:
				AudioServer.set_bus_mute(idx, data[mute_key])
