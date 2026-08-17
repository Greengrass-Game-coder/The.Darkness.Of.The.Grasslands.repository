extends Node
# SFXManager — autoload for procedural sound effects

## Provides simple beep/tones for UI and gameplay sounds.
## Call: SFXManager.play_click() or SFXManager.play_sfx("click")

const SAMPLE_RATE: float = 44100.0

var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	# Pre-create a pool of audio players
	for i in range(4):
		var ap := AudioStreamPlayer.new()
		ap.name = "SFXPlayer_%d" % i
		ap.bus = &"SFX"
		add_child(ap)
		_players.append(ap)


func play_sfx(sfx_name: String) -> void:
	match sfx_name.to_lower():
		"click":
			_play_tone(440.0, 0.08, 0.3)
		"beep":
			_play_tone(660.0, 0.1, 0.3)
		"puzzle_complete":
			_play_tone(880.0, 0.4, 0.4)  # Rising
		"countdown":
			_play_tone(440.0, 0.15, 0.5)
		"ability":
			_play_tone(550.0, 0.15, 0.2)
		"hit":
			_play_tone(150.0, 0.2, 0.5)
		_:
			push_warning("SFXManager: Unknown sound: ", sfx_name)


func _play_tone(freq: float, duration: float, volume: float) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = max(duration, 0.5)
	
	var player := _get_free_player()
	if not player:
		return
	player.stream = generator
	player.volume_db = linear_to_db(volume)
	player.play()
	
	# Fill the buffer with a sine wave
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if not playback:
		return
	
	var frames: int = int(SAMPLE_RATE * duration)
	var increment: float = freq / SAMPLE_RATE
	var phase: float = 0.0
	
	for i in range(frames):
		var sample: float = sin(phase * TAU) * 0.3
		playback.push_frame(Vector2(sample, sample))  # Stereo
		phase += increment
	
	# Fill remaining buffer with silence
	while playback.get_frames_available() > 0:
		playback.push_frame(Vector2.ZERO)


func _get_free_player() -> AudioStreamPlayer:
	for ap in _players:
		if not ap.playing:
			return ap
	return _players[0] if _players.size() > 0 else null


# ═══════════════ Convenience wrappers ═══════════════

func play_click() -> void:
	play_sfx("click")

func play_beep() -> void:
	play_sfx("beep")

func play_puzzle_complete() -> void:
	play_sfx("puzzle_complete")

func play_countdown() -> void:
	play_sfx("countdown")

func play_ability() -> void:
	play_sfx("ability")

func play_hit() -> void:
	play_sfx("hit")
