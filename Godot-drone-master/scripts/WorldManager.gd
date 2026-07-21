extends Node3D

@onready var menu_scene = preload("res://scenes/Menu.tscn")
var menu_instance: CanvasLayer
var vr_manager: Node
var current_environment: BaseEnvironment = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Add FPS Counter
	var fps_counter = preload("res://scripts/FPSCounter.gd").new()
	add_child(fps_counter)
	
	# Initial VR Setup
	vr_manager = load("res://scripts/VRManager.gd").new()
	vr_manager.name = "VRManager"
	add_child(vr_manager)
	
	# Instantiate menu once at startup
	menu_instance = menu_scene.instantiate()
	add_child(menu_instance)
	menu_instance.hide()
	
	# Load default environment
	load_environment(MapEarthDay)
	
	# Setup window and auto-detect screen resolution
	_setup_window_and_resolution()

func _setup_window_and_resolution():
	# If running headless (e.g. running unit tests), do not apply window settings
	if DisplayServer.get_name() == "headless":
		return
		
	# If running in VR, let VRManager handle the window (it needs its own setup)
	if vr_manager and vr_manager.has_method("is_vr_active") and vr_manager.is_vr_active():
		return
		
	# Detect screen resolution
	var screen_index = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen_index)
	
	print("WorldManager: Auto-detected screen resolution: %dx%d" % [screen_size.x, screen_size.y])
	
	# Defer window setting to ensure OS window initialization is complete
	call_deferred("_apply_window_settings", screen_index, screen_size)

func _apply_window_settings(screen_index: int, screen_size: Vector2i):
	DisplayServer.window_set_current_screen(screen_index)
	DisplayServer.window_set_size(screen_size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func load_environment(EnvironmentClass):
	if current_environment:
		current_environment.queue_free()
		current_environment = null
	
	current_environment = EnvironmentClass.new()
	current_environment.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(current_environment)

func _input(event):
	# Listen for ESC key globally
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if menu_instance:
			if menu_instance.visible:
				menu_instance.resume()
			else:
				menu_instance.pause()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_1:
			load_environment(MapEarthDay)
		elif event.keycode == KEY_2:
			load_environment(MapEarthNight)
		elif event.keycode == KEY_3:
			load_environment(MapMoon)
		elif event.keycode == KEY_4:
			load_environment(MapIndoor)
		elif event.keycode == KEY_R:
			if menu_instance:
				menu_instance.resume()
			call_deferred("_restart_fresh")
			get_viewport().set_input_as_handled()

func _toggle_fullscreen():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720)) # reasonable windowed size
		# Center the window on the screen
		var screen_index = DisplayServer.window_get_current_screen()
		var screen_size = DisplayServer.screen_get_size(screen_index)
		var window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen_size - window_size) / 2)
	else:
		var screen_index = DisplayServer.window_get_current_screen()
		var screen_size = DisplayServer.screen_get_size(screen_index)
		DisplayServer.window_set_size(screen_size)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _restart_fresh():
	if get_tree():
		get_tree().reload_current_scene()
