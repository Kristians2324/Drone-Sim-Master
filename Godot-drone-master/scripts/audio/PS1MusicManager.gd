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
			tree.current_scene.add_child(mgr)
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

## Fast, lightweight procedural synthesis of a balanced music loop
func generate_ps1_dnb_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = 44100 * 4 # 4.0 seconds music loop
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var chords = [
		[146.83, 174.61, 220.00, 261.63, 329.63], # Dm9
		[174.61, 220.00, 261.63, 329.63, 349.23], # Fmaj7
	]
	var sub_freqs = [73.42, 87.31]
	var sixteenth_dur = 0.09375 # 160 BPM

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var bar = int(t / 2.0) % 2
		var step_t = fmod(t, sixteenth_dur)
		var step_idx = int(t / sixteenth_dur) % 16

		# 1. Liquid Ambient Synth Pad
		var chord = chords[bar]
		var pad_l = 0.0
		var pad_r = 0.0
		for f_idx in range(chord.size()):
			var freq = chord[f_idx]
			var osc1 = sin(TAU * freq * t) * 0.25
			var osc2 = sin(TAU * (freq * 1.003) * t + 0.4) * 0.25
			var weight = 1.0 / float(f_idx + 1)
			pad_l += osc1 * weight
			pad_r += osc2 * weight
		
		pad_l *= (0.8 + 0.2 * sin(TAU * 0.5 * t))
		pad_r *= (0.8 + 0.2 * sin(TAU * 0.5 * t + 0.5))

		# 2. Sub-Bass
		var sub_f = sub_freqs[bar]
		var sub_sound = sin(TAU * sub_f * t) * 0.28

		# 3. Smooth Rhythm
		var kick = 0.0
		if step_idx in [0, 6, 10, 14]:
			var k_env = exp(-22.0 * step_t)
			var k_freq = 130.0 * exp(-28.0 * step_t) + 48.0
			kick = sin(TAU * k_freq * t) * k_env * 0.40

		var snare = 0.0
		if step_idx in [4, 12]:
			var s_env = exp(-24.0 * step_t)
			var s_noise = (randf() * 2.0 - 1.0) * 0.35
			var s_tone = sin(TAU * 210.0 * t) * 0.30
			snare = (s_tone + s_noise) * s_env * 0.30

		var hat_env = exp(-55.0 * step_t) * (0.5 if step_idx % 2 == 0 else 0.3)
		var hat = (randf() * 2.0 - 1.0) * hat_env * 0.15

		var mix_l = (pad_l * 0.18) + (sub_sound * 0.15) + (kick * 0.12) + (snare * 0.08) + (hat * 0.05)
		var mix_r = (pad_r * 0.18) + (sub_sound * 0.15) + (kick * 0.12) + (snare * 0.08) + (hat * 0.04)

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
