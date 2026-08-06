extends Node
class_name PS1MusicManager

## Music Manager
## Handles background music volume, toggle state, and playback.

static var instance: PS1MusicManager = null
static var global_music_enabled: bool = true
static var global_volume_db: float = -24.0 # Soft background volume

var music_player: AudioStreamPlayer = null
var stream_wav: AudioStreamWAV = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instance = self
	setup_music_player()

static func get_instance() -> PS1MusicManager:
	if instance == null or not is_instance_valid(instance):
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.current_scene:
			var mgr = PS1MusicManager.new()
			mgr.name = "PS1MusicManager"
			tree.current_scene.add_child.call_deferred(mgr)
			instance = mgr
	return instance

func setup_music_player() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, false)
		if AudioServer.get_bus_volume_db(master_idx) < -15.0:
			AudioServer.set_bus_volume_db(master_idx, 0.0)

	if music_player == null:
		music_player = AudioStreamPlayer.new()
		music_player.name = "PS1MusicPlayer"
		music_player.bus = "Master"
		music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(music_player)

	if stream_wav == null:
		stream_wav = generate_ps1_dnb_wav()

	if music_player and stream_wav:
		music_player.stream = stream_wav
		music_player.volume_db = global_volume_db if global_music_enabled else -80.0
		music_player.stream_paused = not global_music_enabled
		if global_music_enabled and not music_player.playing:
			music_player.play()

func set_music_enabled(enabled: bool) -> void:
	global_music_enabled = enabled
	if music_player:
		music_player.volume_db = global_volume_db if global_music_enabled else -80.0
		music_player.stream_paused = not enabled
		if enabled and not music_player.playing:
			music_player.play()

func set_volume_db(vol_db: float) -> void:
	global_volume_db = clampf(vol_db, -80.0, 6.0)
	if music_player:
		music_player.volume_db = global_volume_db if global_music_enabled else -80.0

func update_flight_dynamics(drone_speed: float, delta: float = 0.016) -> void:
	if not global_music_enabled or not music_player:
		return
	
	if not music_player.playing:
		music_player.play()

	var speed_ratio = clampf(drone_speed / 30.0, 0.0, 1.0)
	var target_pitch = 1.0 + (speed_ratio * 0.04)
	music_player.pitch_scale = lerpf(music_player.pitch_scale, target_pitch, clampf(delta * 4.0, 0.05, 1.0))

## Fast, lightweight procedural synthesis of a seamless music loop (Dopo Goto - A Song To Fall Through Textures style)
func generate_ps1_dnb_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	# 160 BPM: 4 bars of 4/4 = 16 beats = exactly 6.0 seconds (264,600 samples)
	var bpm = 160.0
	var seconds_per_beat = 60.0 / bpm
	var total_beats = 16.0
	var duration = total_beats * seconds_per_beat # 6.0s
	var num_samples = int(duration * 44100.0) # 264,600 samples

	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var chords = [
		[146.83, 174.61, 220.00, 261.63, 329.63], # Dm9 (D3, F3, A3, C4, E4)
		[130.81, 164.81, 196.00, 246.94, 329.63], # Cmaj7 (C3, E3, G3, B3, E4)
		[110.00, 130.81, 164.81, 196.00, 261.63], # Am7 (A2, C3, E3, G3, C4)
		[87.31,  130.81, 174.61, 220.00, 261.63]  # Fmaj7 (F2, C3, F3, A3, C4)
	]
	var sub_freqs = [73.42, 65.41, 55.00, 43.65] # Deep sub-bass roots (D2, C2, A1, F1)
	var high_chimes = [440.00, 523.25, 659.25, 523.25] # Floating high sine chimes

	var sixteenth_dur = seconds_per_beat / 4.0
	var fade_samples = int(44100.0 * 0.020)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var beat = t / seconds_per_beat
		var bar = int(beat / 4.0) % 4
		var step_t = fmod(t, sixteenth_dur)
		var step_idx = int(beat * 4.0) % 16

		# 1. Floating Ethereal Liquid Synth Pad
		var chord = chords[bar]
		var pad_l = 0.0
		var pad_r = 0.0
		for f_idx in range(chord.size()):
			var freq = chord[f_idx]
			var osc1 = sin(TAU * freq * t) * 0.22 + (abs(fmod(t * freq, 1.0) - 0.5) - 0.25) * 0.12
			var osc2 = sin(TAU * (freq * 1.0025) * t + 0.4) * 0.22 + (abs(fmod(t * (freq * 1.0025), 1.0) - 0.5) - 0.25) * 0.12
			var weight = 1.0 / float(f_idx + 1)
			pad_l += osc1 * weight
			pad_r += osc2 * weight
		
		var lfo_phase = (t / duration) * TAU
		pad_l *= (0.85 + 0.15 * sin(lfo_phase))
		pad_r *= (0.85 + 0.15 * sin(lfo_phase + 0.6))

		# Floating High Chime Melody
		var chime_f = high_chimes[bar]
		var chime_env = exp(-8.0 * fmod(t, seconds_per_beat * 2.0))
		var chime_out = sin(TAU * chime_f * t) * chime_env * 0.08

		# 2. Smooth Warm 90s Sub-Bass
		var sub_f = sub_freqs[bar]
		var sub_sound = sin(TAU * sub_f * t) * 0.32

		# 3. Shuffled 90s Atmospheric Jungle Breakbeat
		var kick = 0.0
		if step_idx in [0, 6, 10]:
			var k_env = exp(-24.0 * step_t)
			var k_freq = 135.0 * exp(-30.0 * step_t) + 45.0
			kick = sin(TAU * k_freq * t) * k_env * 0.35

		var snare = 0.0
		if step_idx in [4, 12]:
			var s_env = exp(-22.0 * step_t)
			var s_noise = (randf() * 2.0 - 1.0) * 0.30
			var s_tone = sin(TAU * 220.0 * t) * 0.25
			snare = (s_tone + s_noise) * s_env * 0.25
		elif step_idx in [7, 11]:
			var s_env = exp(-35.0 * step_t) * 0.3
			var s_noise = (randf() * 2.0 - 1.0) * 0.15
			snare = s_noise * s_env * 0.15

		var hat_env = exp(-60.0 * step_t) * (0.45 if step_idx % 2 == 0 else 0.25)
		var hat = (randf() * 2.0 - 1.0) * hat_env * 0.12

		var mix_l = (pad_l * 0.16) + chime_out + (sub_sound * 0.16) + (kick * 0.10) + (snare * 0.07) + (hat * 0.04)
		var mix_r = (pad_r * 0.16) + chime_out + (sub_sound * 0.16) + (kick * 0.10) + (snare * 0.07) + (hat * 0.035)

		# Apply 20ms Seamless Loop Fade at start and end
		var fade_factor = 1.0
		if i < fade_samples:
			fade_factor = float(i) / float(fade_samples)
		elif i > (num_samples - fade_samples):
			fade_factor = float(num_samples - i) / float(fade_samples)

		mix_l *= fade_factor
		mix_r *= fade_factor

		var int_l = int(clampf(mix_l * 0.35, -0.95, 0.95) * 32767.0)
		var int_r = int(clampf(mix_r * 0.35, -0.95, 0.95) * 32767.0)

		var b0_l = int_l & 0xFF
		var b1_l = (int_l >> 8) & 0xFF
		var b0_r = int_r & 0xFF
		var b1_r = (int_r >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0_l
		byte_array[idx + 1] = b1_l
		byte_array[idx + 2] = b0_r
		byte_array[idx + 3] = b1_r

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = num_samples
	return wav
