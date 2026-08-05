extends Node3D

const menu_scene = preload("res://scenes/Menu.tscn")
const start_menu_scene = preload("res://scenes/StartMenu.tscn")
const loading_screen_scene = preload("res://scenes/LoadingScreen.tscn")
const tutorial_scene = preload("res://scenes/TutorialOverlay.tscn")
const minimap_scene = preload("res://scenes/Minimap.tscn")
var menu_instance: CanvasLayer
var start_menu_instance: CanvasLayer
var loading_screen_instance: CanvasLayer
var tutorial_instance: CanvasLayer
var minimap_instance: CanvasLayer
var vr_manager: Node
var hardware_settings: Node
var current_environment: BaseEnvironment = null

func _enter_tree():
	if not loading_screen_instance:
		loading_screen_instance = loading_screen_scene.instantiate()
		add_child(loading_screen_instance)
		loading_screen_instance.hide()

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	hardware_settings = load("res://scripts/core/HardwareSettingsManager.gd").new()
	hardware_settings.name = "HardwareSettingsManager"
	add_child(hardware_settings)

	if not loading_screen_instance:
		loading_screen_instance = loading_screen_scene.instantiate()
		add_child(loading_screen_instance)
		loading_screen_instance.hide()

	vr_manager = load("res://scripts/VRManager.gd").new()
	vr_manager.name = "VRManager"
	add_child(vr_manager)

	menu_instance = menu_scene.instantiate()
	add_child(menu_instance)
	menu_instance.hide()

	start_menu_instance = start_menu_scene.instantiate()
	add_child(start_menu_instance)
	if start_menu_instance.has_signal("simulation_started"):
		start_menu_instance.simulation_started.connect(_on_simulation_started)

	minimap_instance = minimap_scene.instantiate()
	add_child(minimap_instance)

	load_environment(MapEarthNight)
	_sync_env_setting(1)
	call_deferred("reapply_user_settings")

	_setup_window_and_resolution()

	if DisplayServer.get_name() != "headless":
		get_tree().paused = true
		if start_menu_instance and start_menu_instance.has_method("open_menu"):
			start_menu_instance.open_menu()
	else:
		if start_menu_instance:
			start_menu_instance.hide()

func _on_simulation_started():
	get_tree().paused = false
	if loading_screen_instance and loading_screen_instance.has_method("hide_loading"):
		loading_screen_instance.hide_loading()
	elif loading_screen_instance:
		loading_screen_instance.hide()

func open_start_menu():
	if menu_instance and menu_instance.visible:
		menu_instance.resume()
	get_tree().paused = true
	if start_menu_instance and start_menu_instance.has_method("open_menu"):
		start_menu_instance.open_menu()

func start_tutorial() -> void:
	if not tutorial_instance or not is_instance_valid(tutorial_instance):
		tutorial_instance = tutorial_scene.instantiate()
		add_child(tutorial_instance)

	if tutorial_instance:
		if tutorial_instance.has_signal("tutorial_completed") and not tutorial_instance.tutorial_completed.is_connected(_on_tutorial_completed):
			tutorial_instance.tutorial_completed.connect(_on_tutorial_completed)
		get_tree().paused = true
		if tutorial_instance.has_method("start_tutorial"):
			tutorial_instance.start_tutorial()

func _on_tutorial_completed() -> void:
	get_tree().paused = false

func _setup_window_and_resolution():
	if DisplayServer.get_name() == "headless":
		return

	if vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active():
		return

	var screen_index = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen_index)

	print("WorldManager: Auto-detected screen resolution: %dx%d" % [screen_size.x, screen_size.y])
	call_deferred("_apply_window_settings", screen_index, screen_size)

func _apply_window_settings(screen_index: int, screen_size: Vector2i):
	DisplayServer.window_set_current_screen(screen_index)
	DisplayServer.window_set_size(screen_size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

var is_loading_environment: bool = false

func load_environment(EnvironmentClass):
	if is_loading_environment:
		return
	if current_environment and current_environment.get_script() == EnvironmentClass:
		return
	if menu_instance and menu_instance.has_method("stop_recording"):
		menu_instance.stop_recording()

	is_loading_environment = true

	var env_name_str = "MAP ENVIRONMENT"
	if EnvironmentClass == MapEarthDay: env_name_str = "EARTH DAY"
	elif EnvironmentClass == MapEarthNight: env_name_str = "EARTH NIGHT"
	elif EnvironmentClass == MapMoon: env_name_str = "MOON SURFACE"
	elif EnvironmentClass == MapIndoor: env_name_str = "INDOOR WAREHOUSE"

	if current_environment != null and loading_screen_instance and loading_screen_instance.has_method("show_loading") and DisplayServer.get_name() != "headless":
		loading_screen_instance.show_loading("Clearing previous environment resources...")
		if get_tree():
			await get_tree().process_frame

	if current_environment:
		current_environment.queue_free()
		current_environment = null
		if get_tree():
			await get_tree().process_frame

	if loading_screen_instance and loading_screen_instance.has_method("show_loading") and DisplayServer.get_name() != "headless":
		loading_screen_instance.show_loading("Building " + env_name_str + " geometry & lighting...")
		if get_tree():
			await get_tree().process_frame

	current_environment = EnvironmentClass.new()
	current_environment.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(current_environment)

	update_ambient_audio(EnvironmentClass)

	if loading_screen_instance and loading_screen_instance.has_method("show_loading") and DisplayServer.get_name() != "headless":
		loading_screen_instance.show_loading("Calibrating drone physics & spatial audio...")
		if get_tree():
			await get_tree().process_frame
			await get_tree().physics_frame

	# Re-apply all active user settings (fog, lighting, shadows, wind, drone physics, volume, etc.) to the new map
	reapply_user_settings()

	if loading_screen_instance and loading_screen_instance.has_method("hide_loading"):
		loading_screen_instance.hide_loading()
	elif loading_screen_instance:
		loading_screen_instance.hide()

	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr and toast_mgr.has_method("show_toast"):
		toast_mgr.show_toast("ENVIRONMENT LOADED: " + env_name_str)

	is_loading_environment = false

func reapply_user_settings() -> void:
	var opts = _find_options_menu(get_tree().root if get_tree() else self)
	if opts and opts.has_method("apply_all_current_settings"):
		opts.apply_all_current_settings()

func _sync_env_setting(env_idx: int) -> void:
	var opts = _find_options_menu(get_tree().root if get_tree() else self)
	if opts and "settings" in opts:
		opts.settings["environment"] = env_idx
		if opts.has_method("_set_control_value"):
			opts._set_control_value("environment", env_idx)

func _find_options_menu(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	if node.get_script() and node.get_script().resource_path.ends_with("DetailedOptionsMenu.gd"):
		return node
	for child in node.get_children():
		var found = _find_options_menu(child)
		if found != null:
			return found
	return null

func _input(event):
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if menu_instance:
			if menu_instance.visible:
				menu_instance.resume()
			else:
				menu_instance.pause()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if (menu_instance and menu_instance.visible) or get_tree().paused or (get_viewport() and get_viewport().gui_get_focus_owner() != null):
			return
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_1:
			_sync_env_setting(0)
			load_environment(MapEarthDay)
		elif event.keycode == KEY_2:
			_sync_env_setting(1)
			load_environment(MapEarthNight)
		elif event.keycode == KEY_3:
			_sync_env_setting(2)
			load_environment(MapMoon)
		elif event.keycode == KEY_4:
			_sync_env_setting(3)
			load_environment(MapIndoor)
		elif event.keycode == KEY_F12 or event.keycode == KEY_P:
			if menu_instance and menu_instance.has_method("take_screenshot"):
				menu_instance.take_screenshot()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			if menu_instance:
				menu_instance.resume()
			call_deferred("_restart_fresh")
			get_viewport().set_input_as_handled()

func _toggle_fullscreen():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		var screen_index = DisplayServer.window_get_current_screen()
		var screen_size = DisplayServer.screen_get_size(screen_index)
		var window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen_size - window_size) / 2)
	else:
		var screen_index = DisplayServer.window_get_current_screen()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _restart_fresh():
	var mgr = get_node_or_null("DroneControllerManager")
	if mgr and mgr.has_method("cleanup"):
		mgr.cleanup()

	get_tree().reload_current_scene()

var ambient_audio_player: AudioStreamPlayer = null

func update_ambient_audio(EnvironmentClass) -> void:
	if ambient_audio_player == null:
		ambient_audio_player = AudioStreamPlayer.new()
		ambient_audio_player.name = "EnvironmentAmbientAudio"
		ambient_audio_player.bus = "Master"
		ambient_audio_player.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(ambient_audio_player)

	var env_str = str(EnvironmentClass)
	if "EarthDay" in env_str or EnvironmentClass == MapEarthDay:
		ambient_audio_player.stream = _build_ambient_day_wav()
		ambient_audio_player.volume_db = -32.0
	elif "Indoor" in env_str or EnvironmentClass == MapIndoor:
		ambient_audio_player.stream = _build_ambient_indoor_wav()
		ambient_audio_player.volume_db = -34.0
	elif "Moon" in env_str or EnvironmentClass == MapMoon:
		ambient_audio_player.stream = _build_ambient_moon_wav()
		ambient_audio_player.volume_db = -28.0
	else:
		ambient_audio_player.stream = _build_ambient_night_wav()
		ambient_audio_player.volume_db = -32.0

	if not ambient_audio_player.playing:
		ambient_audio_player.play()

static func _build_ambient_day_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 2.0)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var wind_lfo = 0.7 + 0.3 * sin(TAU * 0.3 * t)
		var low_hum = sin(TAU * 55.0 * t) * 0.15 + sin(TAU * 110.0 * t) * 0.08
		var sample_val = clampf(low_hum * wind_lfo * 0.25, -0.95, 0.95)
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

static func _build_ambient_night_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 2.0)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var breeze = 0.5 + 0.5 * sin(TAU * 0.2 * t)
		var low_sub = sin(TAU * 50.0 * t) * 0.12
		var sample_val = clampf(low_sub * breeze * 0.2, -0.95, 0.95)
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

static func _build_ambient_moon_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 2.0)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var sub1 = sin(TAU * 45.0 * t) * 0.4
		var sub2 = sin(TAU * 90.0 * t) * 0.25
		var sample_val = clampf((sub1 + sub2) * 0.45, -0.95, 0.95)
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

static func _build_ambient_indoor_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 2.0)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	for i in range(num_samples):
		var t = float(i) / 44100.0
		var hvac = sin(TAU * 110.0 * t) * 0.15 + sin(TAU * 220.0 * t) * 0.08
		var n = (randf() * 2.0 - 1.0) * 0.05
		var sample_val = clampf((hvac + n) * 0.3, -0.95, 0.95)
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
