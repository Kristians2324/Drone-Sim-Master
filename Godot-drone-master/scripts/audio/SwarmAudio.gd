extends Node3D
class_name SwarmAudio

## Dedicated Aggregate Swarm Audio Manager
## Single 3D spatial emitter representing the entire drone flock/light show.
## Soft, balanced, non-intrusive background sound level.

static var shared_swarm_stream: AudioStreamWAV = null

var swarm_player_3d: AudioStreamPlayer3D = null
var swarm_enabled: bool = true
var user_volume_db: float = -24.0 # Soft, quiet, distant background swarm hum
var current_count: int = 15

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	setup_swarm_audio()

func setup_swarm_audio() -> void:
	if shared_swarm_stream == null:
		shared_swarm_stream = build_swarm_buzz_wav()

	if swarm_player_3d == null:
		swarm_player_3d = AudioStreamPlayer3D.new()
		swarm_player_3d.name = "SwarmAudio3D"
		swarm_player_3d.unit_size = 14.0
		swarm_player_3d.max_distance = 350.0
		swarm_player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		swarm_player_3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		swarm_player_3d.panning_strength = 1.0
		swarm_player_3d.bus = "Master"
		if shared_swarm_stream:
			swarm_player_3d.stream = shared_swarm_stream
		add_child(swarm_player_3d)

func set_swarm_enabled(enabled: bool) -> void:
	swarm_enabled = enabled
	if swarm_player_3d:
		if swarm_enabled:
			if not swarm_player_3d.playing:
				swarm_player_3d.play()
			swarm_player_3d.stream_paused = false
		else:
			swarm_player_3d.stream_paused = true
			swarm_player_3d.volume_db = -80.0

func set_user_volume_db(vol_db: float) -> void:
	user_volume_db = clampf(vol_db, -80.0, 6.0)

func update_swarm_audio(center_pos: Vector3, avg_speed: float, count: int, delta: float = 0.016) -> void:
	if not swarm_enabled or not is_inside_tree() or (get_tree() and get_tree().paused):
		if swarm_player_3d:
			swarm_player_3d.stream_paused = true
			swarm_player_3d.volume_db = -80.0
		return

	if count <= 0:
		if swarm_player_3d:
			swarm_player_3d.stream_paused = true
		return

	current_count = count
	global_position = center_pos

	if swarm_player_3d:
		if not swarm_player_3d.playing and shared_swarm_stream:
			swarm_player_3d.play()
		
		swarm_player_3d.stream_paused = false

		# Soft, distant, quiet background swarm hum (-18 dB max)
		var log_count_boost = (log(float(max(count, 1))) / log(2.0)) * 1.0
		var base_vol = user_volume_db
		var speed_vol_boost = clampf(avg_speed / 20.0, 0.0, 1.0) * 1.5
		var target_vol = clampf(base_vol + log_count_boost + speed_vol_boost, -38.0, -18.0)

		var target_pitch = clampf(0.95 + (avg_speed / 30.0) * 0.12, 0.88, 1.20)

		var dt = clampf(delta * 6.0, 0.05, 1.0)
		var cur_vol = swarm_player_3d.volume_db if not is_nan(swarm_player_3d.volume_db) and not is_inf(swarm_player_3d.volume_db) else -28.0
		var cur_pitch = swarm_player_3d.pitch_scale if not is_nan(swarm_player_3d.pitch_scale) and not is_inf(swarm_player_3d.pitch_scale) else 1.0

		swarm_player_3d.volume_db = clampf(lerpf(cur_vol, target_vol, dt), -80.0, 6.0)
		swarm_player_3d.pitch_scale = clampf(lerpf(cur_pitch, target_pitch, dt), 0.5, 2.0)

## Generates a smooth, rich multi-rotor hive roar (2 seconds loop)
static func build_swarm_buzz_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = 44100 * 2 # 2 seconds
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var f0 = 110.0 # Fundamental pitch A2

	var prev_l = 0.0
	var prev_r = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0

		# Rich multi-rotor harmonic stack
		var s0 = sin(TAU * f0 * t) * 0.45
		var s1 = sin(TAU * (f0 * 1.006) * t + 0.3) * 0.35
		var s2 = sin(TAU * (f0 * 0.994) * t + 0.7) * 0.35
		var s3 = sin(TAU * (f0 * 2.01) * t + 1.1) * 0.22 # Blade passing 1st harmonic
		var s4 = sin(TAU * (f0 * 3.015) * t + 1.8) * 0.15 # Blade passing 2nd harmonic
		var sub = sin(TAU * 55.0 * t) * 0.25 # Deep rotor air rumble

		# Multi-phase chop modulation simulating multiple rotor phase interference
		var chop_l = 0.85 + 0.15 * sin(TAU * 12.0 * t + 0.2)
		var chop_r = 0.85 + 0.15 * sin(TAU * 13.5 * t + 0.8)

		var raw_l = (s0 + s1 + s3 + sub) * chop_l * 0.55
		var raw_r = (s0 + s2 + s4 + sub) * chop_r * 0.55

		# 1-pole filter smoothing
		prev_l = lerpf(prev_l, raw_l, 0.35)
		prev_r = lerpf(prev_r, raw_r, 0.35)

		var int_l = int(clampf(prev_l, -0.95, 0.95) * 32767.0)
		var int_r = int(clampf(prev_r, -0.95, 0.95) * 32767.0)

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
