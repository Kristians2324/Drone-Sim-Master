extends Node
class_name DroneAudio

var motor_audio_2d: AudioStreamPlayer
var motor_audio_3d: AudioStreamPlayer3D
var crash_audio_2d: AudioStreamPlayer
var crash_audio_3d: AudioStreamPlayer3D
var whoosh_audio_2d: AudioStreamPlayer
var beep_audio_2d: AudioStreamPlayer
var trick_audio_2d: AudioStreamPlayer

static var shared_motor_stream: AudioStreamWAV = null
static var shared_crash_stream: AudioStreamWAV = null
static var shared_whoosh_stream: AudioStreamWAV = null
static var shared_beep_stream: AudioStreamWAV = null
static var shared_trick_stream: AudioStreamWAV = null

var audio_enabled: bool = true

func initialize() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not motor_audio_2d:
		setup_motor_audio()
	if not crash_audio_2d:
		setup_crash_audio()
	if not whoosh_audio_2d:
		setup_extra_audio()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(_delta: float) -> void:

	if get_tree() and get_tree().paused:
		if whoosh_audio_2d:
			whoosh_audio_2d.stream_paused = true
			whoosh_audio_2d.volume_db = -80.0
		if motor_audio_2d:
			motor_audio_2d.stream_paused = true
			motor_audio_2d.volume_db = -80.0
		if motor_audio_3d:
			motor_audio_3d.stream_paused = true
			motor_audio_3d.volume_db = -80.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		_start_playback_if_ready()

static func _ensure_shared_streams() -> void:
	if shared_motor_stream == null:
		shared_motor_stream = _build_motor_wav()
	if shared_crash_stream == null:
		shared_crash_stream = _build_crash_wav()
	if shared_whoosh_stream == null:
		shared_whoosh_stream = _build_whoosh_wav()
	if shared_beep_stream == null:
		shared_beep_stream = _build_beep_wav()
	if shared_trick_stream == null:
		shared_trick_stream = _build_trick_whoosh_wav()

static func _build_motor_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = 44100 * 2 # 2 seconds
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var f0 = 100.0
	var f_chop = 16.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var s0 = sin(TAU * f0 * t)
		var s1 = sin(TAU * f0 * 2.0 * t) * 0.35
		var s2 = sin(TAU * f0 * 3.0 * t) * 0.15
		var s_sub = sin(TAU * f0 * 0.5 * t) * 0.25
		var chop = 1.0 + 0.12 * sin(TAU * f_chop * t)

		var sample_val = clampf((s0 + s1 + s2 + s_sub) * chop * 0.35, -0.95, 0.95)
		var int_val = int(sample_val * 32767.0)

		var b0 = int_val & 0xFF
		var b1 = (int_val >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0
		byte_array[idx + 1] = b1
		byte_array[idx + 2] = b0
		byte_array[idx + 3] = b1

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = num_samples
	return wav

static func _build_crash_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.5) # 0.5 seconds
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay = exp(-8.0 * t)
		var f_thump = 70.0 * exp(-15.0 * t) + 25.0
		var s_thump = sin(TAU * f_thump * t) * 0.6
		var s_noise = (randf() * 2.0 - 1.0) * 0.5
		var sample_val = clampf((s_thump + s_noise) * decay * 0.7, -0.95, 0.95)
		var int_val = int(sample_val * 32767.0)

		var b0 = int_val & 0xFF
		var b1 = (int_val >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0
		byte_array[idx + 1] = b1
		byte_array[idx + 2] = b0
		byte_array[idx + 3] = b1

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav

static func _build_whoosh_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 1.5)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	# Warm, smooth low-frequency sine air rumble - ZERO harsh white noise!
	for i in range(num_samples):
		var t = float(i) / 44100.0
		var r0 = sin(TAU * 85.0 * t) * 0.4
		var r1 = sin(TAU * 135.0 * t) * 0.25
		var mod = 0.85 + 0.15 * sin(TAU * 1.5 * t)
		var sample_val = clampf((r0 + r1) * mod * 0.35, -0.95, 0.95)
		var int_val = int(sample_val * 32767.0)

		var b0 = int_val & 0xFF
		var b1 = (int_val >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0
		byte_array[idx + 1] = b1
		byte_array[idx + 2] = b0
		byte_array[idx + 3] = b1

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = num_samples
	return wav

static func _build_beep_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.08)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay = exp(-40.0 * t)
		var s = sin(TAU * 1750.0 * t) * 0.65
		var sample_val = clampf(s * decay, -0.95, 0.95)
		var int_val = int(sample_val * 32767.0)

		var b0 = int_val & 0xFF
		var b1 = (int_val >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0
		byte_array[idx + 1] = b1
		byte_array[idx + 2] = b0
		byte_array[idx + 3] = b1

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav

static func _build_trick_whoosh_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.55)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var env = sin(PI * (t / 0.55))
		var f_sweep = 180.0 + (sin(t * 10.0) * 80.0) + (env * 350.0)
		var n = (randf() * 2.0 - 1.0) * 0.4
		var s = sin(TAU * f_sweep * t) * 0.5
		var sample_val = clampf((n + s) * env * 0.7, -0.95, 0.95)
		var int_val = int(sample_val * 32767.0)

		var b0 = int_val & 0xFF
		var b1 = (int_val >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0
		byte_array[idx + 1] = b1
		byte_array[idx + 2] = b0
		byte_array[idx + 3] = b1

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav

func _start_playback_if_ready() -> void:
	if not is_inside_tree():
		return

	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, false)
		if AudioServer.get_bus_volume_db(master_idx) < -25.0:
			AudioServer.set_bus_volume_db(master_idx, 0.0)

	_ensure_shared_streams()

	if motor_audio_2d and shared_motor_stream:
		if motor_audio_2d.stream != shared_motor_stream:
			motor_audio_2d.stream = shared_motor_stream
		if not motor_audio_2d.playing:
			motor_audio_2d.play()
		motor_audio_2d.stream_paused = not audio_enabled
		motor_audio_2d.volume_db = -4.0 if audio_enabled else -80.0

	if motor_audio_3d and shared_motor_stream:
		if motor_audio_3d.stream != shared_motor_stream:
			motor_audio_3d.stream = shared_motor_stream
		if not motor_audio_3d.playing:
			motor_audio_3d.play()
		motor_audio_3d.stream_paused = not audio_enabled
		motor_audio_3d.volume_db = -2.0 if audio_enabled else -80.0

func setup_motor_audio() -> void:
	_ensure_shared_streams()

	motor_audio_2d = AudioStreamPlayer.new()
	motor_audio_2d.name = "MotorAudio2D"
	motor_audio_2d.bus = "Master"
	if shared_motor_stream:
		motor_audio_2d.stream = shared_motor_stream
	add_child(motor_audio_2d)

	motor_audio_3d = AudioStreamPlayer3D.new()
	motor_audio_3d.name = "MotorAudio3D"
	motor_audio_3d.unit_size = 25.0
	motor_audio_3d.max_distance = 500.0
	motor_audio_3d.bus = "Master"
	if shared_motor_stream:
		motor_audio_3d.stream = shared_motor_stream
	add_child(motor_audio_3d)

	_start_playback_if_ready()

func setup_crash_audio() -> void:
	_ensure_shared_streams()

	crash_audio_2d = AudioStreamPlayer.new()
	crash_audio_2d.name = "CrashAudio2D"
	crash_audio_2d.bus = "Master"
	if shared_crash_stream:
		crash_audio_2d.stream = shared_crash_stream
	add_child(crash_audio_2d)

	crash_audio_3d = AudioStreamPlayer3D.new()
	crash_audio_3d.name = "CrashAudio3D"
	crash_audio_3d.unit_size = 35.0
	crash_audio_3d.max_distance = 500.0
	crash_audio_3d.bus = "Master"
	if shared_crash_stream:
		crash_audio_3d.stream = shared_crash_stream
	add_child(crash_audio_3d)

	_start_playback_if_ready()

func setup_extra_audio() -> void:
	_ensure_shared_streams()

	whoosh_audio_2d = AudioStreamPlayer.new()
	whoosh_audio_2d.name = "WhooshAudio2D"
	whoosh_audio_2d.bus = "Master"
	whoosh_audio_2d.stream = shared_whoosh_stream
	add_child(whoosh_audio_2d)

	beep_audio_2d = AudioStreamPlayer.new()
	beep_audio_2d.name = "BeepAudio2D"
	beep_audio_2d.bus = "Master"
	beep_audio_2d.stream = shared_beep_stream
	add_child(beep_audio_2d)

	trick_audio_2d = AudioStreamPlayer.new()
	trick_audio_2d.name = "TrickAudio2D"
	trick_audio_2d.bus = "Master"
	trick_audio_2d.stream = shared_trick_stream
	add_child(trick_audio_2d)

func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	_start_playback_if_ready()

func update_flight_audio(input_vec: Vector4, velocity: Vector3, delta: float = 0.016) -> void:
	if not audio_enabled or not is_inside_tree() or (get_tree() and get_tree().paused):
		if motor_audio_3d:
			motor_audio_3d.stream_paused = true
			motor_audio_3d.volume_db = -80.0
		if motor_audio_2d:
			motor_audio_2d.stream_paused = true
			motor_audio_2d.volume_db = -80.0
		if whoosh_audio_2d:
			whoosh_audio_2d.stream_paused = true
			whoosh_audio_2d.volume_db = -80.0
		return

	if is_nan(velocity.x) or is_nan(velocity.y) or is_nan(velocity.z) or is_inf(velocity.x) or is_inf(velocity.y) or is_inf(velocity.z):
		velocity = Vector3.ZERO
	if is_nan(input_vec.x) or is_nan(input_vec.y) or is_nan(input_vec.z) or is_nan(input_vec.w) or is_inf(input_vec.x) or is_inf(input_vec.y) or is_inf(input_vec.z) or is_inf(input_vec.w):
		input_vec = Vector4.ZERO

	if motor_audio_2d and not motor_audio_2d.playing and shared_motor_stream:
		motor_audio_2d.play()
	if motor_audio_3d and not motor_audio_3d.playing and shared_motor_stream:
		motor_audio_3d.play()

	# Distinct Directional Audio Pitch & Volume Synthesis
	var base_pitch := 0.88

	# 1. THRUST AXIS (UP vs DOWN):
	var thrust_pitch := 0.0
	var thrust_vol := 0.0
	if input_vec.x > 0.0:
		thrust_pitch = input_vec.x * 0.72  # High RPM motor scream when climbing UP (+0.72 pitch)
		thrust_vol = input_vec.x * 6.5
	elif input_vec.x < 0.0:
		thrust_pitch = input_vec.x * 0.28  # Deeper low-prop-wash descent hum when going DOWN (-0.28 pitch)
		thrust_vol = input_vec.x * 2.5

	# 2. PITCH AXIS (FORWARD vs BACKWARD):
	var pitch_dir_mod := 0.0
	var pitch_vol := 0.0
	if input_vec.z < 0.0:
		pitch_dir_mod = abs(input_vec.z) * 0.42 # Crisp forward flight turbine scream
		pitch_vol = abs(input_vec.z) * 4.5
	elif input_vec.z > 0.0:
		pitch_dir_mod = -abs(input_vec.z) * 0.18 # Heavy reverse braking prop chop
		pitch_vol = abs(input_vec.z) * 3.0

	# 3. ROLL AXIS (LEFT vs RIGHT):
	var roll_dir_mod = abs(input_vec.w) * 0.32 # Sharp lateral roll/strafe whine
	var roll_vol = abs(input_vec.w) * 3.5

	# 4. YAW AXIS (YAW LEFT / YAW RIGHT):
	var yaw_dir_mod = abs(input_vec.y) * 0.22 # Differential rotor spin buzz
	var yaw_vol = abs(input_vec.y) * 2.5

	# 5. MOVEMENT SPEED:
	var speed_pitch = clampf(velocity.length() / 22.0, 0.0, 0.38)
	var speed_vol = clampf(velocity.length() / 18.0, 0.0, 1.0) * 4.5

	var target_pitch = clampf(base_pitch + thrust_pitch + pitch_dir_mod + roll_dir_mod + yaw_dir_mod + speed_pitch, 0.55, 2.30)
	var target_vol_db = clampf(-17.0 + thrust_vol + pitch_vol + roll_vol + yaw_vol + speed_vol, -25.0, -4.0)

	var dt = clampf(delta * 12.0, 0.05, 1.0)

	if motor_audio_2d:
		motor_audio_2d.stream_paused = false
		var cur_p2d = motor_audio_2d.pitch_scale if not is_nan(motor_audio_2d.pitch_scale) and not is_inf(motor_audio_2d.pitch_scale) else 1.0
		var cur_v2d = motor_audio_2d.volume_db if not is_nan(motor_audio_2d.volume_db) and not is_inf(motor_audio_2d.volume_db) else -16.0
		motor_audio_2d.pitch_scale = clampf(lerpf(cur_p2d, target_pitch, dt), 0.1, 4.0)
		motor_audio_2d.volume_db = clampf(lerpf(cur_v2d, target_vol_db - 3.0, dt), -80.0, 24.0)

	if motor_audio_3d:
		motor_audio_3d.stream_paused = false
		var cur_p3d = motor_audio_3d.pitch_scale if not is_nan(motor_audio_3d.pitch_scale) and not is_inf(motor_audio_3d.pitch_scale) else 1.0
		var cur_v3d = motor_audio_3d.volume_db if not is_nan(motor_audio_3d.volume_db) and not is_inf(motor_audio_3d.volume_db) else -16.0
		motor_audio_3d.pitch_scale = clampf(lerpf(cur_p3d, target_pitch, dt), 0.1, 4.0)
		motor_audio_3d.volume_db = clampf(lerpf(cur_v3d, target_vol_db, dt), -80.0, 24.0)

	# Dynamic Speed & Wind Whoosh Audio - Triggers dynamically on forward flight and fast movements
	if whoosh_audio_2d and shared_whoosh_stream:
		if not whoosh_audio_2d.playing:
			whoosh_audio_2d.play()
		# Lower trigger threshold to 6.0 m/s when pitching forward for immediate responsive wind feedback
		var forward_bias = 4.0 if input_vec.z < 0.0 else 0.0
		var speed_thresh = maxf(12.0 - forward_bias, 6.0)
		var speed_ratio = clampf((velocity.length() - speed_thresh) / 12.0, 0.0, 1.0)
		if speed_ratio > 0.01:
			whoosh_audio_2d.stream_paused = false
			var cur_wp = whoosh_audio_2d.pitch_scale if not is_nan(whoosh_audio_2d.pitch_scale) and not is_inf(whoosh_audio_2d.pitch_scale) else 1.0
			var cur_wv = whoosh_audio_2d.volume_db if not is_nan(whoosh_audio_2d.volume_db) and not is_inf(whoosh_audio_2d.volume_db) else -42.0
			whoosh_audio_2d.pitch_scale = clampf(lerpf(cur_wp, 0.92 + speed_ratio * 0.32, clampf(delta * 6.0, 0.05, 1.0)), 0.1, 4.0)
			whoosh_audio_2d.volume_db = clampf(lerpf(cur_wv, -38.0 + (speed_ratio * 14.0), clampf(delta * 6.0, 0.05, 1.0)), -80.0, 24.0)
		else:
			whoosh_audio_2d.stream_paused = true
			whoosh_audio_2d.volume_db = -80.0

func update_audio(throttle: float) -> void:
	update_flight_audio(Vector4(throttle, 0, 0, 0), Vector3.ZERO, 0.016)

func play_telemetry_beep(is_urgent: bool = false) -> void:
	if not audio_enabled or not is_inside_tree() or not beep_audio_2d:
		return
	beep_audio_2d.pitch_scale = 1.65 if is_urgent else 1.15
	beep_audio_2d.volume_db = -8.0 if is_urgent else -14.0
	beep_audio_2d.play()

func play_trick_whoosh() -> void:
	if not audio_enabled or not is_inside_tree() or not trick_audio_2d:
		return
	trick_audio_2d.pitch_scale = randf_range(0.95, 1.05)
	trick_audio_2d.volume_db = -6.0
	trick_audio_2d.play()

func play_crash(intensity: float) -> void:
	if not audio_enabled or not is_inside_tree() or not shared_crash_stream:
		return

	if is_nan(intensity) or is_inf(intensity) or intensity < 0.0:
		intensity = 0.0

	var pitch = clampf(1.2 - (intensity / 30.0), 0.7, 1.3)
	var vol_db = clampf(-16.0 + (intensity * 1.2), -18.0, -4.0)

	if crash_audio_2d:
		crash_audio_2d.pitch_scale = clampf(pitch, 0.1, 4.0)
		crash_audio_2d.volume_db = clampf(vol_db - 3.0, -80.0, 24.0)
		crash_audio_2d.play()

	if crash_audio_3d:
		crash_audio_3d.pitch_scale = clampf(pitch, 0.1, 4.0)
		crash_audio_3d.volume_db = clampf(vol_db, -80.0, 24.0)
		crash_audio_3d.play()