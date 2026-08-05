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

	if motor_audio_2d and not motor_audio_2d.playing and shared_motor_stream:
		motor_audio_2d.play()
	if motor_audio_3d and not motor_audio_3d.playing and shared_motor_stream:
		motor_audio_3d.play()

	# Responsive motor load calculation across ALL flight inputs (thrust, pitch, roll, yaw, speed)
	var thrust_load = abs(input_vec.x)
	var pitch_load  = abs(input_vec.z) * 0.70
	var roll_load   = abs(input_vec.w) * 0.70
	var yaw_load    = abs(input_vec.y) * 0.45
	var speed_load  = clamp(velocity.length() / 25.0, 0.0, 0.45)

	var target_load = clamp(thrust_load + pitch_load + roll_load + yaw_load + speed_load, 0.0, 1.0)

	# Pitch scale: 0.85 (smooth idle hum) -> 1.75 (full flight rev)
	var target_pitch = 0.85 + (target_load * 0.90)
	# Volume scale: -16 dB (quiet idle) -> -9 dB (comfortable full flight)
	var target_vol_db = -16.0 + (target_load * 7.0)

	if motor_audio_2d:
		motor_audio_2d.stream_paused = false
		motor_audio_2d.pitch_scale = lerpf(motor_audio_2d.pitch_scale, target_pitch, clamp(delta * 10.0, 0.05, 1.0))
		motor_audio_2d.volume_db = lerpf(motor_audio_2d.volume_db, target_vol_db - 3.0, clamp(delta * 10.0, 0.05, 1.0))

	if motor_audio_3d:
		motor_audio_3d.stream_paused = false
		motor_audio_3d.pitch_scale = lerpf(motor_audio_3d.pitch_scale, target_pitch, clamp(delta * 10.0, 0.05, 1.0))
		motor_audio_3d.volume_db = lerpf(motor_audio_3d.volume_db, target_vol_db, clamp(delta * 10.0, 0.05, 1.0))

	# Dynamic Speed & Wind Whoosh Audio - High speed dives/sprints ONLY (18+ m/s)
	if whoosh_audio_2d and shared_whoosh_stream:
		if not whoosh_audio_2d.playing:
			whoosh_audio_2d.play()
		# Trigger threshold raised to 18 m/s (completely silent during normal flight & cruising)
		var speed_ratio = clamp((velocity.length() - 18.0) / 12.0, 0.0, 1.0)
		if speed_ratio > 0.01:
			whoosh_audio_2d.stream_paused = false
			whoosh_audio_2d.pitch_scale = lerpf(whoosh_audio_2d.pitch_scale, 0.95 + speed_ratio * 0.25, clamp(delta * 6.0, 0.05, 1.0))
			whoosh_audio_2d.volume_db = lerpf(whoosh_audio_2d.volume_db, -42.0 + (speed_ratio * 14.0), clamp(delta * 6.0, 0.05, 1.0)) # Max -28 dB subtle whisper
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

	var pitch = clamp(1.2 - (intensity / 30.0), 0.7, 1.3)
	var vol_db = clamp(-16.0 + (intensity * 1.2), -18.0, -4.0)

	if crash_audio_2d:
		crash_audio_2d.pitch_scale = pitch
		crash_audio_2d.volume_db = vol_db - 3.0
		crash_audio_2d.play()

	if crash_audio_3d:
		crash_audio_3d.pitch_scale = pitch
		crash_audio_3d.volume_db = vol_db
		crash_audio_3d.play()