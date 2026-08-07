extends Node
class_name DroneAudio

var motor_audio_2d: AudioStreamPlayer
var motor_audio_2d_B: AudioStreamPlayer
var motor_audio_3d: AudioStreamPlayer3D
var motor_audio_3d_B: AudioStreamPlayer3D
var crash_audio_2d: AudioStreamPlayer
var crash_audio_3d: AudioStreamPlayer3D
var whoosh_audio_2d: AudioStreamPlayer
var beep_audio_2d: AudioStreamPlayer
var trick_audio_2d: AudioStreamPlayer
var blade_scrape_audio_2d: AudioStreamPlayer
var blade_scrape_audio_3d: AudioStreamPlayer3D

var granular_timer: float = 0.0
var active_voice: int = 0
var voice_fade_timer: float = 1.0

static var shared_motor_stream: AudioStream = null
static var shared_crash_stream: AudioStream = null
static var shared_startup_chirp_stream: AudioStream = null
static var shared_whoosh_stream: AudioStreamWAV = null
static var shared_beep_stream: AudioStreamWAV = null
static var shared_trick_stream: AudioStreamWAV = null
static var shared_blade_scrape_stream: AudioStreamWAV = null
var startup_audio_2d: AudioStreamPlayer
var startup_played: bool = false

static var shared_concrete_stream: AudioStreamWAV = null
static var shared_tree_stream: AudioStreamWAV = null
static var shared_grass_stream: AudioStreamWAV = null
static var shared_metal_stream: AudioStreamWAV = null
static var shared_landing_stream: AudioStreamWAV = null
static var shared_ceiling_stream: AudioStreamWAV = null

static var shared_propeller_hit_stream: AudioStreamWAV = null
static var shared_body_hit_stream: AudioStreamWAV = null
static var shared_belly_hit_stream: AudioStreamWAV = null
static var shared_top_hit_stream: AudioStreamWAV = null
static var shared_tarp_stream: AudioStreamWAV = null

var audio_enabled: bool = true
var is_first_person: bool = true
var view_mode_blend: float = 1.0

func set_first_person(is_fp: bool) -> void:
	is_first_person = is_fp

func set_camera_mode(is_fp: bool) -> void:
	is_first_person = is_fp

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

static func _ensure_shared_streams() -> void:
	if shared_motor_stream == null:
		if ResourceLoader.exists("res://assets/sound/Real_prop_hover.mp3"):
			var loaded_mp3 = load("res://assets/sound/Real_prop_hover.mp3") as AudioStreamMP3
			if loaded_mp3:
				loaded_mp3.loop = true
				shared_motor_stream = loaded_mp3
		elif ResourceLoader.exists("res://assets/sound/Real_Drone_Sound.mp3"):
			var loaded_mp3 = load("res://assets/sound/Real_Drone_Sound.mp3") as AudioStreamMP3
			if loaded_mp3:
				loaded_mp3.loop = true
				shared_motor_stream = loaded_mp3
		elif ResourceLoader.exists("res://assets/sound/drone_motor.wav"):
			var loaded_motor = load("res://assets/sound/drone_motor.wav") as AudioStreamWAV
			if loaded_motor:
				loaded_motor.loop_mode = AudioStreamWAV.LOOP_FORWARD
				shared_motor_stream = loaded_motor
		if shared_motor_stream == null:
			shared_motor_stream = _build_motor_wav()

	if shared_crash_stream == null:
		if ResourceLoader.exists("res://assets/sound/Real_Crash.flac"):
			var loaded_flac = load("res://assets/sound/Real_Crash.flac")
			if loaded_flac:
				shared_crash_stream = loaded_flac
		elif ResourceLoader.exists("res://assets/sound/drone_crash.wav"):
			var loaded_crash = load("res://assets/sound/drone_crash.wav") as AudioStreamWAV
			if loaded_crash:
				shared_crash_stream = loaded_crash
		if shared_crash_stream == null:
			shared_crash_stream = _build_crash_wav()
	if shared_startup_chirp_stream == null and ResourceLoader.exists("res://assets/sound/drone_startup_chirp.wav"):
		shared_startup_chirp_stream = load("res://assets/sound/drone_startup_chirp.wav")
	if shared_whoosh_stream == null:
		shared_whoosh_stream = _build_whoosh_wav()
	if shared_beep_stream == null:
		shared_beep_stream = _build_beep_wav()
	if shared_trick_stream == null:
		shared_trick_stream = _build_trick_whoosh_wav()
	if shared_blade_scrape_stream == null:
		shared_blade_scrape_stream = _build_blade_scrape_wav()
	if shared_concrete_stream == null:
		shared_concrete_stream = _build_concrete_impact_wav()
	if shared_tree_stream == null:
		shared_tree_stream = _build_tree_impact_wav()
	if shared_grass_stream == null:
		shared_grass_stream = _build_grass_impact_wav()
	if shared_metal_stream == null:
		shared_metal_stream = _build_metal_impact_wav()
	if shared_landing_stream == null:
		shared_landing_stream = _build_hard_landing_wav()
	if shared_ceiling_stream == null:
		shared_ceiling_stream = _build_ceiling_impact_wav()
	if shared_propeller_hit_stream == null:
		shared_propeller_hit_stream = _build_propeller_hit_wav()
	if shared_body_hit_stream == null:
		shared_body_hit_stream = _build_body_hit_wav()
	if shared_belly_hit_stream == null:
		shared_belly_hit_stream = _build_belly_hit_wav()
	if shared_top_hit_stream == null:
		shared_top_hit_stream = _build_top_hit_wav()
	if shared_tarp_stream == null:
		shared_tarp_stream = _build_tarp_impact_wav()

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

	var num_samples = int(44100 * 0.25) # Short 0.25s realistic plastic prop snap & frame thud
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_noise = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0

		# 1. Carbon Frame Thud (low-mid plastic/frame impact, ~140Hz decaying fast)
		var decay_thud = exp(-28.0 * t)
		var f_thud = 140.0 * exp(-12.0 * t) + 40.0
		var s_thud = sin(TAU * f_thud * t) * 0.5 * decay_thud

		# 2. Plastic Propeller Blade Snap (dry plastic clack, lowpass filtered to eliminate cymbal sizzle!)
		var decay_snap = exp(-35.0 * t)
		var raw_noise = (randf() * 2.0 - 1.0)
		prev_noise = lerpf(prev_noise, raw_noise, 0.12) # 1-pole lowpass filter removing harsh metallic highs
		var s_snap = prev_noise * 0.45 * decay_snap

		# 3. Propeller Blade Slap (transient pulse)
		var slap_env = exp(-60.0 * t)
		var s_slap = sin(TAU * 320.0 * t) * 0.3 * slap_env

		var sample_val = clampf((s_thud + s_snap + s_slap) * 0.55, -0.95, 0.95)
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

static func _build_blade_scrape_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.35) # 0.35s blade wall scrape & cutting sound
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay = exp(-10.0 * t)

		# High frequency blade chop (600 - 1200 Hz fast chopping pulse train matching spinning props)
		var f_chop = 750.0 + 350.0 * sin(TAU * 50.0 * t)
		var s_chop = sign(sin(TAU * f_chop * t)) * 0.4 * decay

		# High-frequency friction scratching sound (blades cutting wall)
		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.4) # High pass wall cutting friction noise
		var s_scrape = prev_n * 0.5 * decay

		var sample_val = clampf((s_chop + s_scrape) * 0.5, -0.95, 0.95)
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
	if not is_inside_tree() or not audio_enabled:
		return

	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, false)
		if AudioServer.get_bus_volume_db(master_idx) < -25.0:
			AudioServer.set_bus_volume_db(master_idx, 0.0)

	_ensure_shared_streams()

	if motor_audio_2d and shared_motor_stream and not motor_audio_2d.playing:
		motor_audio_2d.stream = shared_motor_stream.duplicate()
		motor_audio_2d.volume_db = -80.0
		motor_audio_2d.play()

	if motor_audio_3d and shared_motor_stream and not motor_audio_3d.playing:
		motor_audio_3d.stream = shared_motor_stream.duplicate()
		motor_audio_3d.volume_db = -80.0
		motor_audio_3d.play()

	if not startup_played and shared_startup_chirp_stream:
		startup_played = true
		play_startup_chirp()

func play_startup_chirp() -> void:
	if not audio_enabled or not is_inside_tree() or not shared_startup_chirp_stream:
		return
	if get_tree() and get_tree().paused:
		return
	if startup_audio_2d == null:
		startup_audio_2d = AudioStreamPlayer.new()
		startup_audio_2d.name = "StartupChirpAudio2D"
		startup_audio_2d.bus = "Master"
		add_child(startup_audio_2d)
	startup_audio_2d.stream = shared_startup_chirp_stream.duplicate()
	startup_audio_2d.volume_db = -6.0
	startup_audio_2d.play()

func setup_motor_audio() -> void:
	_ensure_shared_streams()

	motor_audio_2d = AudioStreamPlayer.new()
	motor_audio_2d.name = "MotorAudio2D_A"
	motor_audio_2d.bus = "Master"
	motor_audio_2d.volume_db = -80.0
	if shared_motor_stream:
		motor_audio_2d.stream = shared_motor_stream.duplicate()
	add_child(motor_audio_2d)

	motor_audio_2d_B = AudioStreamPlayer.new()
	motor_audio_2d_B.name = "MotorAudio2D_B"
	motor_audio_2d_B.bus = "Master"
	motor_audio_2d_B.volume_db = -80.0
	if shared_motor_stream:
		motor_audio_2d_B.stream = shared_motor_stream.duplicate()
	add_child(motor_audio_2d_B)

	motor_audio_3d = AudioStreamPlayer3D.new()
	motor_audio_3d.name = "MotorAudio3D_A"
	motor_audio_3d.unit_size = 45.0
	motor_audio_3d.max_distance = 1200.0
	motor_audio_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	motor_audio_3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	motor_audio_3d.panning_strength = 1.0
	motor_audio_3d.bus = "Master"
	motor_audio_3d.volume_db = -80.0
	if shared_motor_stream:
		motor_audio_3d.stream = shared_motor_stream.duplicate()
	add_child(motor_audio_3d)

	motor_audio_3d_B = AudioStreamPlayer3D.new()
	motor_audio_3d_B.name = "MotorAudio3D_B"
	motor_audio_3d_B.unit_size = 45.0
	motor_audio_3d_B.max_distance = 1200.0
	motor_audio_3d_B.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	motor_audio_3d_B.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	motor_audio_3d_B.panning_strength = 1.0
	motor_audio_3d_B.bus = "Master"
	motor_audio_3d_B.volume_db = -80.0
	if shared_motor_stream:
		motor_audio_3d_B.stream = shared_motor_stream.duplicate()
	add_child(motor_audio_3d_B)

	_start_playback_if_ready()

func setup_crash_audio() -> void:
	_ensure_shared_streams()

	crash_audio_2d = AudioStreamPlayer.new()
	crash_audio_2d.name = "CrashAudio2D"
	crash_audio_2d.bus = "Master"
	if shared_crash_stream:
		crash_audio_2d.stream = shared_crash_stream.duplicate()
	add_child(crash_audio_2d)

	crash_audio_3d = AudioStreamPlayer3D.new()
	crash_audio_3d.name = "CrashAudio3D"
	crash_audio_3d.unit_size = 50.0
	crash_audio_3d.max_distance = 1200.0
	crash_audio_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	crash_audio_3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	crash_audio_3d.panning_strength = 1.0
	crash_audio_3d.bus = "Master"
	if shared_crash_stream:
		crash_audio_3d.stream = shared_crash_stream.duplicate()
	add_child(crash_audio_3d)

	blade_scrape_audio_2d = AudioStreamPlayer.new()
	blade_scrape_audio_2d.name = "BladeScrapeAudio2D"
	blade_scrape_audio_2d.bus = "Master"
	if shared_blade_scrape_stream:
		blade_scrape_audio_2d.stream = shared_blade_scrape_stream
	add_child(blade_scrape_audio_2d)

	blade_scrape_audio_3d = AudioStreamPlayer3D.new()
	blade_scrape_audio_3d.name = "BladeScrapeAudio3D"
	blade_scrape_audio_3d.unit_size = 45.0
	blade_scrape_audio_3d.max_distance = 1200.0
	blade_scrape_audio_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	blade_scrape_audio_3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	blade_scrape_audio_3d.panning_strength = 1.0
	blade_scrape_audio_3d.bus = "Master"
	if shared_blade_scrape_stream:
		blade_scrape_audio_3d.stream = shared_blade_scrape_stream
	add_child(blade_scrape_audio_3d)

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
	if not enabled:
		if motor_audio_2d:
			motor_audio_2d.stream_paused = true
			motor_audio_2d.volume_db = -80.0
			motor_audio_2d.stop()
		if motor_audio_2d_B:
			motor_audio_2d_B.stream_paused = true
			motor_audio_2d_B.volume_db = -80.0
			motor_audio_2d_B.stop()
		if motor_audio_3d:
			motor_audio_3d.stream_paused = true
			motor_audio_3d.volume_db = -80.0
			motor_audio_3d.stop()
		if motor_audio_3d_B:
			motor_audio_3d_B.stream_paused = true
			motor_audio_3d_B.volume_db = -80.0
			motor_audio_3d_B.stop()
		if whoosh_audio_2d:
			whoosh_audio_2d.stream_paused = true
			whoosh_audio_2d.volume_db = -80.0
			whoosh_audio_2d.stop()
		if startup_audio_2d:
			startup_audio_2d.stop()
	else:
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

	# Smoothly update view mode blend (1.0 = first person onboard, 0.0 = third person distant 3D)
	var target_blend = 1.0 if is_first_person else 0.0
	view_mode_blend = lerpf(view_mode_blend, target_blend, clampf(delta * 8.0, 0.05, 1.0))

	# Distinct Directional Audio Pitch & Volume Synthesis
	var base_pitch := 0.92

	# 1. THRUST AXIS (UP vs DOWN):
	var thrust_pitch := 0.0
	var thrust_vol := 0.0
	if input_vec.x > 0.0:
		thrust_pitch = input_vec.x * 0.28  # Realistic high RPM motor rise (+0.28 pitch)
		thrust_vol = input_vec.x * 4.0
	elif input_vec.x < 0.0:
		thrust_pitch = input_vec.x * 0.12  # Low-prop-wash descent hum (-0.12 pitch)
		thrust_vol = input_vec.x * 1.5

	# 2. PITCH AXIS (FORWARD vs BACKWARD):
	var pitch_dir_mod := 0.0
	var pitch_vol := 0.0
	if input_vec.z < 0.0:
		pitch_dir_mod = abs(input_vec.z) * 0.16 # Smooth forward flight pitch
		pitch_vol = abs(input_vec.z) * 3.0
	elif input_vec.z > 0.0:
		pitch_dir_mod = -abs(input_vec.z) * 0.08
		pitch_vol = abs(input_vec.z) * 2.0

	# 3. ROLL AXIS (LEFT vs RIGHT):
	var roll_dir_mod = abs(input_vec.w) * 0.14
	var roll_vol = abs(input_vec.w) * 2.5

	# 4. YAW AXIS (YAW LEFT / YAW RIGHT):
	var yaw_dir_mod = abs(input_vec.y) * 0.10
	var yaw_vol = abs(input_vec.y) * 1.8

	# 5. MOVEMENT SPEED:
	var speed_pitch = clampf(velocity.length() / 30.0, 0.0, 0.18)
	var speed_vol = clampf(velocity.length() / 20.0, 0.0, 1.0) * 3.0

	# Refined physical RPM range: 0.82x (hover/descent) to 1.48x (max throttle)
	var time_sec = Time.get_ticks_msec() * 0.001
	var organic_jitter = sin(time_sec * 1.9) * 0.003 + cos(time_sec * 3.3) * 0.002
	var target_pitch = clampf(base_pitch + thrust_pitch + pitch_dir_mod + roll_dir_mod + yaw_dir_mod + speed_pitch + organic_jitter, 0.82, 1.48)
	var target_vol_db = clampf(-12.0 + (thrust_vol + pitch_vol + roll_vol + yaw_vol + speed_vol) * 0.35, -20.0, -4.0)

	# Smooth physical rotor inertia spooling (dt = delta * 4.5 for silky smooth transitions)
	var dt = clampf(delta * 4.5, 0.02, 0.25)

	# Compute 2D and 3D volumes based on view mode:
	var desired_vol_2d = lerpf(target_vol_db - 6.0, target_vol_db - 2.0, view_mode_blend)
	var desired_vol_3d = lerpf(target_vol_db + 2.0, target_vol_db - 4.0, view_mode_blend)

	# In TPV mode (3D distant mode), pitch is slightly lower (deeper prop hum)
	var pitch_3d_mod = lerpf(-0.02, 0.0, view_mode_blend)
	var target_pitch_3d = clampf(target_pitch + pitch_3d_mod, 0.80, 1.46)

	# Dual-Voice Granular Engine: Crossfades Voice A and Voice B every 1.0s to bypass MP3 padding gaps
	granular_timer += delta
	if granular_timer >= 1.0:
		granular_timer = 0.0
		active_voice = 1 - active_voice
		voice_fade_timer = 0.0
		if active_voice == 1:
			if motor_audio_2d_B and shared_motor_stream: motor_audio_2d_B.play(0.2)
			if motor_audio_3d_B and shared_motor_stream: motor_audio_3d_B.play(0.2)
		else:
			if motor_audio_2d and shared_motor_stream: motor_audio_2d.play(0.2)
			if motor_audio_3d and shared_motor_stream: motor_audio_3d.play(0.2)

	voice_fade_timer += delta * 3.5
	var fade_factor = clampf(voice_fade_timer, 0.0, 1.0)

	var vol_2d_A = desired_vol_2d if active_voice == 0 else lerpf(desired_vol_2d, -80.0, fade_factor)
	var vol_2d_B = desired_vol_2d if active_voice == 1 else lerpf(desired_vol_2d, -80.0, fade_factor)
	var vol_3d_A = desired_vol_3d if active_voice == 0 else lerpf(desired_vol_3d, -80.0, fade_factor)
	var vol_3d_B = desired_vol_3d if active_voice == 1 else lerpf(desired_vol_3d, -80.0, fade_factor)

	if motor_audio_2d:
		motor_audio_2d.stream_paused = false
		motor_audio_2d.pitch_scale = clampf(target_pitch, 0.5, 2.5)
		motor_audio_2d.volume_db = clampf(vol_2d_A, -80.0, 6.0)

	if motor_audio_2d_B:
		motor_audio_2d_B.stream_paused = false
		motor_audio_2d_B.pitch_scale = clampf(target_pitch * 1.004, 0.5, 2.5)
		motor_audio_2d_B.volume_db = clampf(vol_2d_B, -80.0, 6.0)

	if motor_audio_3d:
		motor_audio_3d.stream_paused = false
		motor_audio_3d.pitch_scale = clampf(target_pitch_3d, 0.5, 2.5)
		motor_audio_3d.volume_db = clampf(vol_3d_A, -80.0, 6.0)

	if motor_audio_3d_B:
		motor_audio_3d_B.stream_paused = false
		motor_audio_3d_B.pitch_scale = clampf(target_pitch_3d * 1.004, 0.5, 2.5)
		motor_audio_3d_B.volume_db = clampf(vol_3d_B, -80.0, 6.0)

	# Dynamic Speed & Motion Airflow Audio Layering
	if whoosh_audio_2d and shared_whoosh_stream:
		if not whoosh_audio_2d.playing:
			whoosh_audio_2d.play()

		var is_moving = (velocity.length() > 2.0) or (input_vec.length() > 0.1)
		if is_moving and audio_enabled:
			whoosh_audio_2d.stream_paused = false
			var move_intensity = clampf(velocity.length() / 20.0 + input_vec.length() * 0.35, 0.0, 1.0)
			var target_w_vol = clampf(-36.0 + move_intensity * 24.0, -36.0, -12.0)
			var target_w_pitch = clampf(0.85 + move_intensity * 0.40, 0.75, 1.40)
			whoosh_audio_2d.volume_db = lerpf(whoosh_audio_2d.volume_db, target_w_vol, dt)
			whoosh_audio_2d.pitch_scale = lerpf(whoosh_audio_2d.pitch_scale, target_w_pitch, dt)
		else:
			whoosh_audio_2d.volume_db = lerpf(whoosh_audio_2d.volume_db, -80.0, dt * 2.0)
			if whoosh_audio_2d.volume_db < -70.0:
				whoosh_audio_2d.stream_paused = true

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

	var pitch = clampf(1.0 + (randf() * 0.1 - 0.05), 0.85, 1.15)
	var vol_db = clampf(-6.0 + clampf(intensity * 0.8, 0.0, 8.0), -10.0, 2.0)

	if crash_audio_2d and is_first_person:
		crash_audio_2d.stream = shared_crash_stream.duplicate()
		crash_audio_2d.pitch_scale = clampf(pitch, 0.5, 2.0)
		crash_audio_2d.volume_db = clampf(vol_db, -80.0, 6.0)
		crash_audio_2d.play()

	if crash_audio_3d:
		crash_audio_3d.stream = shared_crash_stream.duplicate()
		crash_audio_3d.pitch_scale = clampf(pitch, 0.5, 2.0)
		crash_audio_3d.volume_db = clampf(vol_db + 2.0, -80.0, 6.0)
		crash_audio_3d.play()

func play_blade_scrape(intensity: float) -> void:
	if not audio_enabled or not is_inside_tree() or not shared_blade_scrape_stream:
		return

	if is_nan(intensity) or is_inf(intensity) or intensity < 0.0:
		intensity = 0.0

	var pitch = clampf(1.0 + (randf() * 0.2 - 0.1), 0.85, 1.35)
	var vol_db = clampf(-10.0 + clampf(intensity * 0.8, 0.0, 6.0), -14.0, -2.0)

	if blade_scrape_audio_2d and is_first_person:
		blade_scrape_audio_2d.pitch_scale = clampf(pitch, 0.5, 2.5)
		blade_scrape_audio_2d.volume_db = clampf(vol_db, -80.0, 6.0)
		blade_scrape_audio_2d.play()

	if blade_scrape_audio_3d:
		blade_scrape_audio_3d.pitch_scale = clampf(pitch, 0.5, 2.5)
		blade_scrape_audio_3d.volume_db = clampf(vol_db + 2.0, -80.0, 6.0)
		blade_scrape_audio_3d.play()

func play_surface_impact(impact: float, surface_type: int = 0, hit_zone: int = 0) -> void:
	if not audio_enabled or not is_inside_tree():
		return

	if is_nan(impact) or is_inf(impact) or impact < 0.0:
		impact = 0.0

	var target_stream: AudioStream = shared_crash_stream if shared_crash_stream else shared_concrete_stream

	# Specific material overrides (tarp, tree, grass, metal)
	if surface_type == 4 and shared_tarp_stream: # TARP / CANVAS
		target_stream = shared_tarp_stream
	elif surface_type == 1 and shared_tree_stream: # TREE
		target_stream = shared_tree_stream
	elif surface_type == 2 and shared_grass_stream: # GRASS
		target_stream = shared_grass_stream
	elif surface_type == 3 and shared_metal_stream: # METAL
		target_stream = shared_metal_stream

	if target_stream == null:
		target_stream = shared_crash_stream if shared_crash_stream else shared_concrete_stream

	var pitch = clampf(1.0 + (randf() * 0.16 - 0.08), 0.85, 1.25)
	var vol_db = clampf(-6.0 + clampf(impact * 0.85, 0.0, 10.0), -10.0, 2.0)

	if crash_audio_2d and is_first_person:
		crash_audio_2d.stream = target_stream.duplicate() if target_stream else null
		crash_audio_2d.pitch_scale = clampf(pitch, 0.5, 2.0)
		crash_audio_2d.volume_db = clampf(vol_db, -80.0, 6.0)
		crash_audio_2d.play()

	if crash_audio_3d:
		crash_audio_3d.stream = target_stream.duplicate() if target_stream else null
		crash_audio_3d.pitch_scale = clampf(pitch, 0.5, 2.0)
		crash_audio_3d.volume_db = clampf(vol_db + 2.0, -80.0, 6.0)
		crash_audio_3d.play()

static func _build_concrete_impact_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.32)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_thud = exp(-22.0 * t)
		var f_thud = 160.0 * exp(-18.0 * t) + 45.0
		var s_thud = sin(TAU * f_thud * t) * 0.7 * decay_thud

		var decay_crunch = exp(-32.0 * t)
		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.25)
		var s_crunch = prev_n * 0.6 * decay_crunch
		var s_crack = sin(TAU * 480.0 * t) * 0.4 * exp(-50.0 * t)

		var sample_val = clampf((s_thud + s_crunch + s_crack) * 0.65, -0.95, 0.95)
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

static func _build_tree_impact_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.35)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_thwack = exp(-18.0 * t)
		var f_wood = 220.0 * exp(-14.0 * t) + 60.0
		var s_wood = sin(TAU * f_wood * t) * 0.65 * decay_thwack

		var decay_leaf = exp(-15.0 * t)
		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.5)
		var s_leaf = prev_n * 0.55 * decay_leaf * (0.8 + 0.2 * sin(TAU * 35.0 * t))

		var sample_val = clampf((s_wood + s_leaf) * 0.6, -0.95, 0.95)
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

static func _build_grass_impact_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.28)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_dirt = exp(-25.0 * t)
		var f_dirt = 110.0 * exp(-10.0 * t) + 35.0
		var s_dirt = sin(TAU * f_dirt * t) * 0.6 * decay_dirt

		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.08)
		var s_turf = prev_n * 0.4 * decay_dirt

		var sample_val = clampf((s_dirt + s_turf) * 0.55, -0.95, 0.95)
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

static func _build_metal_impact_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.4)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_impact = exp(-24.0 * t)
		var decay_ring = exp(-12.0 * t)

		var s_clang = sin(TAU * 380.0 * t) * 0.5 * decay_impact
		var s_ring = (sin(TAU * 920.0 * t) + sin(TAU * 1450.0 * t) * 0.5) * 0.35 * decay_ring
		var s_pop = (randf() * 2.0 - 1.0) * 0.3 * exp(-45.0 * t)

		var sample_val = clampf((s_clang + s_ring + s_pop) * 0.55, -0.95, 0.95)
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

static func _build_hard_landing_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.3)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_thud = exp(-20.0 * t)
		var f_land = 130.0 * exp(-16.0 * t) + 40.0
		var s_thud = sin(TAU * f_land * t) * 0.75 * decay_thud
		var s_gear = sin(TAU * 260.0 * t) * 0.4 * exp(-40.0 * t)

		var sample_val = clampf((s_thud + s_gear) * 0.6, -0.95, 0.95)
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

static func _build_ceiling_impact_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.28)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_roof = exp(-26.0 * t)
		var f_roof = 210.0 * exp(-18.0 * t) + 55.0
		var s_thud = sin(TAU * f_roof * t) * 0.65 * decay_roof
		var s_clack = sin(TAU * 520.0 * t) * 0.45 * exp(-45.0 * t)

		var sample_val = clampf((s_thud + s_clack) * 0.6, -0.95, 0.95)
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

static func _build_propeller_hit_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.32)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_chop = exp(-14.0 * t)

		# 1. Fast pitch drop (850 Hz -> 200 Hz violent spinning prop strike)
		var f_prop = 850.0 * exp(-18.0 * t) + 200.0
		var s_prop = sin(TAU * f_prop * t) * 0.7 * decay_chop

		# 2. Rapid spinning 4-blade chopping modulation (120 Hz pulse sequence)
		var chop_pulse = 1.0 + 0.5 * sin(TAU * 120.0 * t)

		# 3. High-frequency carbon blade strike snap
		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.45)
		var s_snap = prev_n * 0.65 * exp(-35.0 * t)

		var sample_val = clampf((s_prop * chop_pulse + s_snap) * 0.75, -0.95, 0.95)
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

static func _build_tarp_impact_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.32)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_fabric = exp(-18.0 * t)
		var f_tarp = 150.0 * exp(-12.0 * t) + 40.0
		var s_tarp = sin(TAU * f_tarp * t) * 0.7 * decay_fabric

		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.15)
		var s_snap = prev_n * 0.5 * exp(-28.0 * t)

		var sample_val = clampf((s_tarp + s_snap) * 0.6, -0.95, 0.95)
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

static func _build_top_hit_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.28)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_shell = exp(-24.0 * t)
		var f_top = 480.0 * exp(-20.0 * t) + 160.0
		var s_thud = sin(TAU * f_top * t) * 0.7 * decay_shell
		var s_pop = sin(TAU * 950.0 * t) * 0.45 * exp(-55.0 * t)

		var sample_val = clampf((s_thud + s_pop) * 0.6, -0.95, 0.95)
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

static func _build_belly_hit_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.32)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_belly = exp(-14.0 * t)
		var f_belly = 65.0 * exp(-10.0 * t) + 32.0
		var s_thud = sin(TAU * f_belly * t) * 0.9 * decay_belly
		var s_gear = sin(TAU * 190.0 * t) * 0.3 * exp(-30.0 * t)

		var sample_val = clampf((s_thud + s_gear) * 0.75, -0.95, 0.95)
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

static func _build_body_hit_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.32)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	var prev_n = 0.0

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay_body = exp(-22.0 * t)
		var f_body = 160.0 * exp(-16.0 * t) + 50.0
		var s_thud = sin(TAU * f_body * t) * 0.75 * decay_body

		var raw_n = (randf() * 2.0 - 1.0)
		prev_n = lerpf(prev_n, raw_n, 0.22)
		var s_crunch = prev_n * 0.55 * exp(-30.0 * t)

		var sample_val = clampf((s_thud + s_crunch) * 0.65, -0.95, 0.95)
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