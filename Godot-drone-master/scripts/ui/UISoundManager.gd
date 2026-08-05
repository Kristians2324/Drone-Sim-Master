extends Node

## Global UI Sound Manager
## Provides satisfying clicky-clack button click sounds and crisp hover audio for all UI elements.

static var instance = null

var hover_stream: AudioStreamWAV
var click_stream: AudioStreamWAV

# AudioStreamPlayer pools for concurrent multi-channel playback
var hover_players: Array[AudioStreamPlayer] = []
var click_players: Array[AudioStreamPlayer] = []
var hover_player_index: int = 0
var click_player_index: int = 0
const POOL_SIZE: int = 8

var hover_volume_db: float = -12.0
var click_volume_db: float = -3.0

func get_hover_stream() -> AudioStreamWAV:
	if hover_stream == null:
		_build_audio_streams()
	return hover_stream

func get_click_stream() -> AudioStreamWAV:
	if click_stream == null:
		_build_audio_streams()
	return click_stream

func _init() -> void:
	instance = self
	_build_audio_streams()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hover_stream == null:
		_build_audio_streams()
	_create_player_pools()
	
	if get_tree():
		get_tree().node_added.connect(_on_node_added)
		_scan_node(get_tree().root)

func _create_player_pools() -> void:
	for i in range(POOL_SIZE):
		var h_player = AudioStreamPlayer.new()
		h_player.name = "UIHoverPlayer_%d" % i
		h_player.bus = "Master"
		h_player.stream = hover_stream
		add_child(h_player)
		hover_players.append(h_player)

		var c_player = AudioStreamPlayer.new()
		c_player.name = "UIClickPlayer_%d" % i
		c_player.bus = "Master"
		c_player.stream = click_stream
		add_child(c_player)
		click_players.append(c_player)

func _scan_node(node: Node) -> void:
	if not node: return
	_register_button(node)
	for child in node.get_children():
		_scan_node(child)

func _on_node_added(node: Node) -> void:
	_register_button(node)

func _register_button(node: Node) -> void:
	if node is BaseButton:
		var btn = node as BaseButton
		if not btn.mouse_entered.is_connected(_on_button_hover.bind(btn)):
			btn.mouse_entered.connect(_on_button_hover.bind(btn))
		if not btn.pressed.is_connected(_on_button_pressed.bind(btn)):
			btn.pressed.connect(_on_button_pressed.bind(btn))

func _on_button_hover(btn: BaseButton) -> void:
	if btn and is_instance_valid(btn) and btn.is_visible_in_tree() and not btn.disabled:
		play_hover_sound()

func _on_button_pressed(_btn: BaseButton) -> void:
	play_click_sound()

func play_hover_sound() -> void:
	if hover_players.size() == 0: return
	var player = hover_players[hover_player_index]
	hover_player_index = (hover_player_index + 1) % POOL_SIZE
	player.volume_db = hover_volume_db
	player.pitch_scale = randf_range(0.96, 1.04) # Subtle organic pitch variation
	player.play()

func play_click_sound() -> void:
	if click_players.size() == 0: return
	var player = click_players[click_player_index]
	click_player_index = (click_player_index + 1) % POOL_SIZE
	player.volume_db = click_volume_db
	player.pitch_scale = randf_range(0.98, 1.02) # Tactile mechanical pitch consistency
	player.play()

func _build_audio_streams() -> void:
	hover_stream = _build_hover_wav()
	click_stream = _build_click_wav()

static func _build_hover_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var duration = 0.03 # 30ms crisp hover blip
	var num_samples = int(44100 * duration)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay = exp(-160.0 * t)
		var f = 1300.0 * exp(-90.0 * t) + 650.0
		var sine_wave = sin(TAU * f * t) * 0.45
		var noise = (randf() * 2.0 - 1.0) * 0.35 * exp(-300.0 * t)
		var sample_val = clampf((sine_wave + noise) * decay * 0.6, -0.95, 0.95)
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

static func _build_click_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var duration = 0.075 # 75ms tactile mechanical switch click-clack
	var num_samples = int(44100 * duration)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0

		# Phase 1: High-frequency metallic switch snap (click) at 0ms
		var click_decay = exp(-220.0 * t)
		var f_click = 2600.0 * exp(-120.0 * t) + 1200.0
		var click_sine = sin(TAU * f_click * t) * 0.6
		var click_noise = (randf() * 2.0 - 1.0) * 0.5 * exp(-280.0 * t)
		var click_val = (click_sine + click_noise) * click_decay

		# Phase 2: Solid mechanical body bottoming-out thud (clack) starting at 12ms
		var clack_val = 0.0
		if t >= 0.012:
			var t2 = t - 0.012
			var clack_decay = exp(-65.0 * t2)
			var f_clack = 650.0 * exp(-40.0 * t2) + 200.0
			var clack_sine = sin(TAU * f_clack * t2) * 0.65
			var clack_noise = (randf() * 2.0 - 1.0) * 0.25 * exp(-150.0 * t2)
			clack_val = (clack_sine + clack_noise) * clack_decay

		var combined = clampf((click_val * 0.65 + clack_val * 0.75) * 0.85, -0.95, 0.95)
		var int_val = int(combined * 32767.0)

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
