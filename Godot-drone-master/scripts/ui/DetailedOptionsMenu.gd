extends Control
class_name DetailedOptionsMenu

const CONFIG_FILE_PATH = "user://drone_sim_settings.cfg"

# Current settings cache
var settings: Dictionary = {
	# Graphics
	"vsync": DisplayServer.VSYNC_ENABLED,
	"window_mode": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	"msaa": Viewport.MSAA_4X,
	"shadow_resolution": 2,
	"fps_cap": 0, # Uncapped
	"render_scale": 1.0,
	"fog_density": 0.0,
	
	# Flight & Physics
	"hover_mode": false,
	"thrust_multiplier": 1.0,
	"turn_sensitivity": 1.0,
	"stabilize_force": 45.0,
	"gravity_scale": 1.0,
	"infinite_battery": false,
	
	# Environment & Weather
	"environment": 1, # 0: Earth Day, 1: Earth Night, 2: Moon, 3: Indoor
	"wind_preset": 0, # 0: Calm (0 m/s)
	"light_energy": 1.0,
	
	# Swarm
	"swarm_active": false,
	"boid_count": 15.0,
	"separation_radius": 3.5,
	"boid_speed": 20.0,
	"led_theme": 0, # 0: Cyan, 1: Emerald, 2: Amber, 3: Magenta, 4: Rainbow
	
	# Audio & Camera
	"master_volume": 1.0,
	"camera_mode": 0, # 0: First Person, 1: Third Person
	"camera_fov": 75.0
}

# UI Node References & Control Registry
var tab_bar: HBoxContainer
var tab_buttons: Dictionary = {}
var tab_contents: Dictionary = {}
var ui_controls: Dictionary = {}
var current_tab: String = "graphics"
var _is_initializing_ui: bool = true

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_initializing_ui = true
	_load_config_from_disk()
	_setup_ui()
	_is_initializing_ui = false
	apply_all_current_settings()

func _load_config_from_disk() -> void:
	var config = ConfigFile.new()
	if config.load(CONFIG_FILE_PATH) == OK:
		for key in settings.keys():
			if config.has_section_key("settings", key):
				settings[key] = config.get_value("settings", key)

func _setup_ui():
	var root_vbox = VBoxContainer.new()
	root_vbox.name = "Layout"
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 10)
	add_child(root_vbox)

	# --- Title Bar ---
	var title = Label.new()
	title.text = "GRAPHICAL CONFIGURATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	root_vbox.add_child(title)

	# --- Tab Bar ---
	tab_bar = HBoxContainer.new()
	tab_bar.name = "TabsHeader"
	tab_bar.add_theme_constant_override("separation", 6)
	root_vbox.add_child(tab_bar)

	var tabs_info = [
		{"id": "graphics", "label": "DISPLAY"},
		{"id": "physics", "label": "PHYSICS"},
		{"id": "env", "label": "WORLD"},
		{"id": "swarm", "label": "SWARM"},
		{"id": "audio_cam", "label": "AUDIO/CAM"},
		{"id": "presets", "label": "PRESETS"}
	]

	for tab in tabs_info:
		var btn = Button.new()
		btn.text = tab["label"]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_tab_clicked.bind(tab["id"]))
		_apply_tab_button_style(btn, false)
		tab_bar.add_child(btn)
		tab_buttons[tab["id"]] = btn

	var separator = HSeparator.new()
	root_vbox.add_child(separator)

	# --- Scroll Container for Tab Content ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var content_margin = MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_left", 6)
	content_margin.add_theme_constant_override("margin_right", 6)
	content_margin.add_theme_constant_override("margin_top", 4)
	content_margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(content_margin)

	var content_stack = PanelContainer.new()
	content_stack.name = "ContentStack"
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var transparent_box = StyleBoxEmpty.new()
	content_stack.add_theme_stylebox_override("panel", transparent_box)
	content_margin.add_child(content_stack)

	# Build tab content containers
	tab_contents["graphics"] = _build_graphics_tab()
	tab_contents["physics"] = _build_physics_tab()
	tab_contents["env"] = _build_env_tab()
	tab_contents["swarm"] = _build_swarm_tab()
	tab_contents["audio_cam"] = _build_audio_cam_tab()
	tab_contents["presets"] = _build_presets_tab()

	for cat in tab_contents.keys():
		content_stack.add_child(tab_contents[cat])

	_switch_tab("graphics")

func _apply_tab_button_style(btn: Button, active: bool):
	var style = StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.2, 0.65, 0.95, 0.45)
		style.border_color = Color(0.2, 0.85, 1.0, 0.9)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		style.bg_color = Color(0.12, 0.16, 0.22, 0.9)
		style.border_color = Color(0.2, 0.65, 0.95, 0.5)
		btn.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.75))

	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

func _on_tab_clicked(tab_id: String):
	_switch_tab(tab_id)

func _switch_tab(tab_id: String):
	current_tab = tab_id
	for key in tab_buttons.keys():
		var btn = tab_buttons[key]
		var is_active = (key == tab_id)
		_apply_tab_button_style(btn, is_active)
		if tab_contents.has(key):
			tab_contents[key].visible = is_active

# --- TAB BUILDERS ---

func _build_graphics_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	vbox.add_child(_create_dropdown_row("vsync", "VSync Mode", ["Disabled", "Enabled", "Adaptive"], 1, _on_vsync_changed))
	vbox.add_child(_create_dropdown_row("window_mode", "Window Mode", ["Exclusive Fullscreen", "Windowed", "Borderless Window"], 0, _on_window_mode_changed))
	vbox.add_child(_create_dropdown_row("msaa", "Anti-Aliasing (MSAA)", ["Disabled", "2x MSAA", "4x MSAA", "8x MSAA"], 2, _on_msaa_changed))
	vbox.add_child(_create_dropdown_row("shadow_resolution", "Shadow Resolution", ["Off", "Low (1024)", "Medium (2048)", "Ultra (4096)"], 2, _on_shadow_quality_changed))
	vbox.add_child(_create_dropdown_row("fps_cap", "Max Frame Rate", ["Uncapped", "30 FPS", "60 FPS", "120 FPS", "144 FPS"], 0, _on_fps_cap_changed))
	vbox.add_child(_create_slider_row("render_scale", "Resolution Scale", 0.5, 1.0, 0.05, 1.0, "%.0f%%", func(val): return val * 100.0, _on_render_scale_changed))
	vbox.add_child(_create_slider_row("fog_density", "Volumetric Fog Haze", 0.0, 100.0, 1.0, 0.0, "%.0f%%", func(v): return v, _on_fog_density_changed))

	vbox.add_child(HSeparator.new())
	vbox.add_child(_create_styled_button("RESET DISPLAY DEFAULTS", _reset_graphics_defaults, Color(0.15, 0.25, 0.35, 0.9)))

	return vbox

func _build_physics_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	vbox.add_child(_create_toggle_row("hover_mode", "Hover Assist Mode", false, _on_hover_toggled))
	vbox.add_child(_create_slider_row("thrust_multiplier", "Thrust Power Multiplier", 0.5, 2.5, 0.1, 1.0, "%.1fx", func(v): return v, _on_thrust_changed))
	vbox.add_child(_create_slider_row("turn_sensitivity", "Control Turn Rate", 0.5, 2.5, 0.1, 1.0, "%.1fx", func(v): return v, _on_turn_sens_changed))
	vbox.add_child(_create_slider_row("stabilize_force", "Gyro Stabilization Force", 10.0, 100.0, 5.0, 45.0, "%.0f", func(v): return v, _on_stabilize_changed))
	vbox.add_child(_create_slider_row("gravity_scale", "Environment Gravity", 0.0, 2.0, 0.1, 1.0, "%.1fg", func(v): return v, _on_gravity_changed))
	vbox.add_child(_create_toggle_row("infinite_battery", "Infinite Battery Supply", false, _on_battery_toggled))

	vbox.add_child(HSeparator.new())
	vbox.add_child(_create_styled_button("RESET PHYSICS DEFAULTS", _reset_physics_defaults, Color(0.15, 0.25, 0.35, 0.9)))

	return vbox

func _build_env_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	vbox.add_child(_create_dropdown_row("environment", "Select Environment", ["Earth (Day)", "Earth (Night)", "Moon Base", "Indoor Arena"], 0, _on_environment_selected))
	vbox.add_child(_create_dropdown_row("wind_preset", "Wind Simulation Profile", ["Calm (0 m/s)", "Light Breeze (5 m/s)", "Moderate (12 m/s)", "Severe Storm (25 m/s)"], 0, _on_wind_preset_changed))
	vbox.add_child(_create_slider_row("light_energy", "Light & Sun Energy", 0.1, 3.0, 0.1, 1.0, "%.1fx", func(v): return v, _on_light_energy_changed))

	vbox.add_child(HSeparator.new())
	vbox.add_child(_create_styled_button("RESET WORLD DEFAULTS", _reset_env_defaults, Color(0.15, 0.25, 0.35, 0.9)))

	return vbox

var custom_img_path_edit: LineEdit = null

func _build_swarm_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	vbox.add_child(_create_toggle_row("swarm_active", "Enable Swarm Mode (Tab)", false, _on_swarm_mode_toggled))
	vbox.add_child(_create_slider_row("boid_count", "Swarm Drone Count", 5.0, 50.0, 1.0, 15.0, "%.0f Drones", func(v): return v, _on_boid_count_changed))
	vbox.add_child(_create_slider_row("separation_radius", "Boid Separation Radius", 1.0, 10.0, 0.5, 3.5, "%.1fm", func(v): return v, _on_separation_changed))
	vbox.add_child(_create_slider_row("boid_speed", "Max Swarm Speed", 5.0, 40.0, 1.0, 20.0, "%.0f m/s", func(v): return v, _on_boid_speed_changed))
	vbox.add_child(_create_dropdown_row("led_theme", "Airshow LED Color Scheme", ["Cyber Cyan", "Emerald Green", "Neon Amber", "Vibrant Magenta", "Pulsing Rainbow"], 0, _on_led_theme_changed))

	vbox.add_child(HSeparator.new())
	vbox.add_child(_create_styled_button("RESET SWARM DEFAULTS", _reset_swarm_defaults, Color(0.15, 0.25, 0.35, 0.9)))

	return vbox

func _build_audio_cam_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	vbox.add_child(_create_slider_row("master_volume", "Master Volume", 0.0, 1.0, 0.05, 1.0, "%.0f%%", func(v): return v * 100.0, _on_volume_changed))
	vbox.add_child(_create_dropdown_row("camera_mode", "Active Camera View", ["First Person (FPV)", "Third Person Chase", "Cinematic Show Cam"], 0, _on_camera_mode_changed))
	vbox.add_child(_create_slider_row("camera_fov", "Camera FOV", 60.0, 110.0, 1.0, 75.0, "%.0f°", func(v): return v, _on_fov_changed))

	vbox.add_child(HSeparator.new())
	vbox.add_child(_create_styled_button("RESET AUDIO/CAM DEFAULTS", _reset_audio_cam_defaults, Color(0.15, 0.25, 0.35, 0.9)))

	return vbox

func _build_presets_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var label = Label.new()
	label.text = "QUICK PERFORMANCE PRESETS"
	label.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	var p_low = _create_styled_button("LOW PERF", func(): _apply_preset("low"))
	var p_med = _create_styled_button("BALANCED", func(): _apply_preset("medium"))
	var p_high = _create_styled_button("HIGH QUALITY", func(): _apply_preset("high"))
	var p_ultra = _create_styled_button("ULTRA / CINEMATIC", func(): _apply_preset("ultra"))

	grid.add_child(p_low)
	grid.add_child(p_med)
	grid.add_child(p_high)
	grid.add_child(p_ultra)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var reset_btn = _create_styled_button("RESET ALL TO DEFAULTS", _reset_defaults, Color(0.85, 0.35, 0.35, 0.9))
	vbox.add_child(reset_btn)

	return vbox

# --- UI HELPER CREATORS & REGISTRY ---

func _create_styled_button(text: String, callback: Callable, custom_color: Color = Color(0.12, 0.16, 0.22, 0.9)) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = custom_color
	style.border_color = Color(0.2, 0.65, 0.95, 0.5)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(callback)
	return btn

func _create_dropdown_row(key: String, label_text: String, options: Array, default_idx: int, callback: Callable) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
	lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(lbl)

	var opt = OptionButton.new()
	opt.custom_minimum_size = Vector2(160, 32)
	for item in options:
		opt.add_item(item)
	var cur_idx = int(settings.get(key, default_idx))
	if cur_idx >= 0 and cur_idx < opt.item_count:
		opt.select(cur_idx)
	elif default_idx >= 0 and default_idx < opt.item_count:
		opt.select(default_idx)

	var opt_style = StyleBoxFlat.new()
	opt_style.bg_color = Color(0.12, 0.16, 0.22, 0.9)
	opt_style.border_color = Color(0.2, 0.65, 0.95, 0.5)
	opt_style.set_border_width_all(1)
	opt_style.corner_radius_top_left = 6
	opt_style.corner_radius_top_right = 6
	opt_style.corner_radius_bottom_right = 6
	opt_style.corner_radius_bottom_left = 6
	opt.add_theme_stylebox_override("normal", opt_style)

	opt.item_selected.connect(callback)
	hbox.add_child(opt)

	ui_controls[key] = {
		"type": "dropdown",
		"node": opt,
		"default": default_idx,
		"callback": callback
	}

	return hbox

func _create_slider_row(key: String, label_text: String, min_val: float, max_val: float, step_val: float, default_val: float, val_format: String, val_transform: Callable, callback: Callable) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var cur_val = float(settings.get(key, default_val))

	var header_hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
	lbl.add_theme_font_size_override("font_size", 13)
	header_hbox.add_child(lbl)

	var val_lbl = Label.new()
	val_lbl.text = val_format % val_transform.call(cur_val)
	val_lbl.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	val_lbl.add_theme_font_size_override("font_size", 13)
	header_hbox.add_child(val_lbl)

	vbox.add_child(header_hbox)

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = cur_val
	slider.custom_minimum_size = Vector2(0, 24)

	slider.value_changed.connect(func(v):
		val_lbl.text = val_format % val_transform.call(v)
		callback.call(v)
	)
	vbox.add_child(slider)

	ui_controls[key] = {
		"type": "slider",
		"node": slider,
		"label": val_lbl,
		"default": default_val,
		"format": val_format,
		"transform": val_transform,
		"callback": callback
	}

	return vbox

func _create_toggle_row(key: String, label_text: String, default_val: bool, callback: Callable) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cur_bool = bool(settings.get(key, default_val))

	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
	lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(lbl)

	var check = CheckButton.new()
	check.button_pressed = cur_bool
	check.toggled.connect(callback)
	hbox.add_child(check)

	ui_controls[key] = {
		"type": "toggle",
		"node": check,
		"default": default_val,
		"callback": callback
	}

	return hbox

# --- PERSISTENT LOCAL DEVICE SETTINGS (CONFIGFILE) ---

func save_user_settings():
	if _is_initializing_ui:
		return
	var config = ConfigFile.new()
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.save(CONFIG_FILE_PATH)

func load_user_settings():
	apply_all_current_settings()

func apply_all_current_settings():
	var config = ConfigFile.new()
	if config.load(CONFIG_FILE_PATH) == OK:
		for key in settings.keys():
			if config.has_section_key("settings", key):
				settings[key] = config.get_value("settings", key)

	for key in ui_controls.keys():
		if settings.has(key):
			_set_control_ui_only(key, settings[key])

	_apply_vsync(int(settings.get("vsync", 1)))
	_apply_window_mode(int(settings.get("window_mode", 0)))
	_apply_msaa(int(settings.get("msaa", 2)))
	_apply_shadow_quality(int(settings.get("shadow_resolution", 2)))
	_apply_fps_cap(int(settings.get("fps_cap", 0)))
	_apply_render_scale(float(settings.get("render_scale", 1.0)))
	_apply_fog_density(float(settings.get("fog_density", 0.0)))
	_apply_light_energy(float(settings.get("light_energy", 1.0)))
	_apply_wind_preset(int(settings.get("wind_preset", 0)))

	var drone = _get_player_drone()
	if drone:
		if drone.has_method("set_hover_mode"):
			drone.set_hover_mode(bool(settings.get("hover_mode", false)))
		drone.speed_multiplier = float(settings.get("thrust_multiplier", 1.0))
		drone.turn_sensitivity_multiplier = float(settings.get("turn_sensitivity", 1.0))
		drone.custom_stabilize_force = float(settings.get("stabilize_force", 45.0))
		drone.gravity_scale = float(settings.get("gravity_scale", 1.0))
		if drone.has_method("set_infinite_battery_enabled"):
			drone.set_infinite_battery_enabled(bool(settings.get("infinite_battery", false)))

	_apply_master_volume(float(settings.get("master_volume", 1.0)))
	_apply_camera_mode(int(settings.get("camera_mode", 0)))
	_apply_camera_fov(float(settings.get("camera_fov", 75.0)))

func _set_control_ui_only(key: String, val: Variant):
	if not ui_controls.has(key):
		return
	var item = ui_controls[key]
	match item["type"]:
		"slider":
			var slider: HSlider = item["node"]
			slider.set_block_signals(true)
			slider.value = float(val)
			slider.set_block_signals(false)
			var val_lbl: Label = item["label"]
			if val_lbl and item["transform"] and item["format"]:
				val_lbl.text = item["format"] % item["transform"].call(float(val))
		"dropdown":
			var opt: OptionButton = item["node"]
			var idx = int(val)
			if idx >= 0 and idx < opt.item_count:
				opt.set_block_signals(true)
				opt.select(idx)
				opt.set_block_signals(false)
		"toggle":
			var check: CheckButton = item["node"]
			check.set_block_signals(true)
			check.button_pressed = bool(val)
			check.set_block_signals(false)

func _set_control_value(key: String, val: Variant):
	_set_control_ui_only(key, val)
	if ui_controls.has(key):
		var item = ui_controls[key]
		match item["type"]:
			"slider": item["callback"].call(float(val))
			"dropdown": item["callback"].call(int(val))
			"toggle": item["callback"].call(bool(val))

# --- CONTROL RESET HELPER ---

func _reset_setting(key: String):
	if not ui_controls.has(key):
		return
	var item = ui_controls[key]
	var def_val = item["default"]
	_set_control_value(key, def_val)
	save_user_settings()

# --- RECURSIVE NODE FINDER HELPERS ---

func _get_all_world_environments() -> Array[WorldEnvironment]:
	var result: Array[WorldEnvironment] = []
	_collect_world_environments(get_tree().root if get_tree() else self, result)
	return result

func _collect_world_environments(node: Node, result: Array[WorldEnvironment]) -> void:
	if node is WorldEnvironment:
		result.append(node as WorldEnvironment)
	for child in node.get_children():
		_collect_world_environments(child, result)

func _get_all_directional_lights() -> Array[DirectionalLight3D]:
	var result: Array[DirectionalLight3D] = []
	_collect_directional_lights(get_tree().root if get_tree() else self, result)
	return result

func _collect_directional_lights(node: Node, result: Array[DirectionalLight3D]) -> void:
	if node is DirectionalLight3D:
		result.append(node as DirectionalLight3D)
	for child in node.get_children():
		_collect_directional_lights(child, result)

# --- SETTINGS APPLICATION HELPERS ---

func _apply_vsync(idx: int):
	var mode = DisplayServer.VSYNC_DISABLED
	if idx == 1: mode = DisplayServer.VSYNC_ENABLED
	elif idx == 2: mode = DisplayServer.VSYNC_ADAPTIVE
	DisplayServer.window_set_vsync_mode(mode)

func _apply_window_mode(idx: int):
	var mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if idx == 1: mode = DisplayServer.WINDOW_MODE_WINDOWED
	elif idx == 2: mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(mode)

func _apply_msaa(idx: int):
	var msaa = Viewport.MSAA_DISABLED
	match idx:
		1: msaa = Viewport.MSAA_2X
		2: msaa = Viewport.MSAA_4X
		3: msaa = Viewport.MSAA_8X
	get_viewport().msaa_3d = msaa

func _apply_shadow_quality(idx: int):
	var lights = _get_all_directional_lights()
	for light in lights:
		if is_instance_valid(light):
			match idx:
				0:
					light.shadow_enabled = false
				1:
					light.shadow_enabled = true
					light.directional_shadow_max_distance = 1024.0
				2:
					light.shadow_enabled = true
					light.directional_shadow_max_distance = 2048.0
				3:
					light.shadow_enabled = true
					light.directional_shadow_max_distance = 4096.0

func _apply_fps_cap(idx: int):
	var fps = 0
	match idx:
		1: fps = 30
		2: fps = 60
		3: fps = 120
		4: fps = 144
	Engine.max_fps = fps

func _apply_render_scale(val: float):
	get_viewport().scaling_3d_scale = val

func _apply_fog_density(val: float):
	settings["fog_density"] = val
	var env_list = _get_all_world_environments()

	for world_env in env_list:
		if world_env and world_env.environment:
			var env = world_env.environment
			env.fog_enabled = false
			if val <= 0.5:
				env.volumetric_fog_enabled = false
			else:
				env.volumetric_fog_enabled = true
				var norm_val = val / 100.0
				var calculated_density = pow(norm_val, 3.0) * 0.0008
				env.volumetric_fog_density = calculated_density
				env.volumetric_fog_length = 600.0
				env.volumetric_fog_sky_affect = 0.05
				env.volumetric_fog_emission_energy = 0.3
				env.volumetric_fog_albedo = Color(0.75, 0.82, 0.9)

func _apply_light_energy(val: float):
	var lights = _get_all_directional_lights()
	for light in lights:
		if is_instance_valid(light):
			light.light_energy = val

func _apply_wind_preset(idx: int):
	var scene = get_tree().current_scene if get_tree() else null
	if scene:
		var wm = scene.find_child("WindManager", true, false) as WindManager
		if wm:
			wm.set_manual_wind_preset(idx)
	var drone = _get_player_drone()
	if drone and drone.has_method("set_wind_profile"):
		match idx:
			0: drone.set_wind_profile(Vector3(1, 0, 0), 0.0, 0.0, "Calm")
			1: drone.set_wind_profile(Vector3(1, 0, 0.5).normalized(), 5.0, 0.15, "Light Breeze")
			2: drone.set_wind_profile(Vector3(1, 0, 1).normalized(), 12.0, 0.35, "Moderate Wind")
			3: drone.set_wind_profile(Vector3(-1, 0, 0.8).normalized(), 25.0, 0.65, "Stormy Gusts")

func _apply_master_volume(val: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(val))

func _apply_camera_mode(idx: int):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager") if get_tree() and get_tree().current_scene else null
	if mgr:
		if idx == 0:
			mgr.is_first_person = true
		elif idx == 1:
			mgr.is_first_person = false
		mgr.update_camera_views()

func _apply_camera_fov(val: float):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager") if get_tree() and get_tree().current_scene else null
	if mgr:
		if mgr.fp_camera: mgr.fp_camera.fov = val
		if mgr.tp_camera: mgr.tp_camera.fov = val

# --- SETTINGS CALLBACK HANDLERS ---

func _on_vsync_changed(idx: int):
	_apply_vsync(idx)
	settings["vsync"] = idx
	save_user_settings()

func _on_window_mode_changed(idx: int):
	_apply_window_mode(idx)
	settings["window_mode"] = idx
	save_user_settings()

func _on_msaa_changed(idx: int):
	_apply_msaa(idx)
	settings["msaa"] = idx
	save_user_settings()

func _on_shadow_quality_changed(idx: int):
	_apply_shadow_quality(idx)
	settings["shadow_resolution"] = idx
	save_user_settings()

func _on_fps_cap_changed(idx: int):
	_apply_fps_cap(idx)
	settings["fps_cap"] = idx
	save_user_settings()

func _on_render_scale_changed(val: float):
	_apply_render_scale(val)
	settings["render_scale"] = val
	save_user_settings()

func _on_fog_density_changed(val: float):
	_apply_fog_density(val)
	settings["fog_density"] = val
	save_user_settings()

func _on_hover_toggled(pressed: bool):
	var drone = _get_player_drone()
	if drone and drone.has_method("set_hover_mode"):
		drone.set_hover_mode(pressed)
	settings["hover_mode"] = pressed
	save_user_settings()

func _on_thrust_changed(val: float):
	var drone = _get_player_drone()
	if drone:
		drone.speed_multiplier = val
	settings["thrust_multiplier"] = val
	save_user_settings()

func _on_turn_sens_changed(val: float):
	var drone = _get_player_drone()
	if drone:
		drone.turn_sensitivity_multiplier = val
	settings["turn_sensitivity"] = val
	save_user_settings()

func _on_stabilize_changed(val: float):
	var drone = _get_player_drone()
	if drone:
		drone.custom_stabilize_force = val
	settings["stabilize_force"] = val
	save_user_settings()

func _on_gravity_changed(val: float):
	var drone = _get_player_drone()
	if drone:
		drone.gravity_scale = val
	settings["gravity_scale"] = val
	save_user_settings()

func _on_battery_toggled(pressed: bool):
	var drone = _get_player_drone()
	if drone and drone.has_method("set_infinite_battery_enabled"):
		drone.set_infinite_battery_enabled(pressed)
	settings["infinite_battery"] = pressed
	save_user_settings()

func _on_environment_selected(idx: int):
	var wm = get_tree().current_scene
	if wm and wm.has_method("load_environment"):
		match idx:
			0: wm.load_environment(load("res://scripts/environments/MapEarthDay.gd"))
			1: wm.load_environment(load("res://scripts/environments/MapEarthNight.gd"))
			2: wm.load_environment(load("res://scripts/environments/MapMoon.gd"))
			3: wm.load_environment(load("res://scripts/environments/MapIndoor.gd"))
	settings["environment"] = idx
	save_user_settings()

func _on_wind_preset_changed(idx: int):
	var scene = get_tree().current_scene
	if scene:
		var wm = scene.find_child("WindManager", true, false) as WindManager
		if wm:
			wm.set_manual_wind_preset(idx)
	var drone = _get_player_drone()
	if drone and drone.has_method("set_wind_profile"):
		match idx:
			0: drone.set_wind_profile(Vector3(1, 0, 0), 0.0, 0.0, "Calm")
			1: drone.set_wind_profile(Vector3(1, 0, 0.5).normalized(), 5.0, 0.15, "Light Breeze")
			2: drone.set_wind_profile(Vector3(1, 0, 1).normalized(), 12.0, 0.35, "Moderate Wind")
			3: drone.set_wind_profile(Vector3(-1, 0, 0.8).normalized(), 25.0, 0.65, "Stormy Gusts")
	settings["wind_preset"] = idx
	save_user_settings()

func _on_light_energy_changed(val: float):
	var light = get_tree().current_scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D if get_tree().current_scene else null
	if light:
		light.light_energy = val
	settings["light_energy"] = val
	save_user_settings()

func _on_swarm_mode_toggled(pressed: bool):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if mgr and mgr.has_method("toggle_swarm_mode"):
		if pressed != mgr.swarm_mode:
			mgr.toggle_swarm_mode()
	settings["swarm_active"] = pressed
	save_user_settings()

func _on_boid_count_changed(val: float):
	settings["boid_count"] = val
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if mgr and mgr.swarm_controller and is_instance_valid(mgr.swarm_controller):
		if mgr.swarm_controller.get("boid_manager"):
			mgr.swarm_controller.boid_manager.boid_count = int(val)
	save_user_settings()

func _on_separation_changed(val: float):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if mgr and mgr.swarm_controller and is_instance_valid(mgr.swarm_controller):
		if mgr.swarm_controller.get("boid_manager"):
			mgr.swarm_controller.boid_manager.separation_radius = val
	settings["separation_radius"] = val
	save_user_settings()

func _on_boid_speed_changed(val: float):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if mgr and mgr.swarm_controller and is_instance_valid(mgr.swarm_controller):
		if mgr.swarm_controller.get("boid_manager"):
			mgr.swarm_controller.boid_manager.max_speed = val
	settings["boid_speed"] = val
	save_user_settings()

func _on_led_theme_changed(idx: int):
	var colors = [
		Color(0.2, 0.85, 1.0), # Cyan
		Color(0.1, 0.9, 0.3), # Emerald
		Color(1.0, 0.6, 0.1), # Amber
		Color(0.95, 0.2, 0.8), # Magenta
		Color(1.0, 1.0, 1.0) # Rainbow
	]
	var selected_color = colors[clamp(idx, 0, colors.size() - 1)]
	var drone = _get_player_drone()
	if drone and is_instance_valid(drone) and "show_rig" in drone and drone.show_rig and is_instance_valid(drone.show_rig):
		if drone.show_rig.has_method("set_color_all"):
			drone.show_rig.set_color_all(selected_color)

	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager") if get_tree() and get_tree().current_scene else null
	if mgr and mgr.swarm_controller and is_instance_valid(mgr.swarm_controller):
		if "drones" in mgr.swarm_controller:
			for d in mgr.swarm_controller.drones:
				if is_instance_valid(d) and "show_rig" in d and d.show_rig and is_instance_valid(d.show_rig):
					if d.show_rig.has_method("set_color_all"):
						d.show_rig.set_color_all(selected_color)

	settings["led_theme"] = idx
	save_user_settings()

func _on_volume_changed(val: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(val))
	settings["master_volume"] = val
	save_user_settings()

func _on_camera_mode_changed(idx: int):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if mgr:
		if idx == 0:
			mgr.is_first_person = true
		elif idx == 1:
			mgr.is_first_person = false
		mgr.update_camera_views()
	settings["camera_mode"] = idx
	save_user_settings()

func _on_fov_changed(val: float):
	var mgr = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if mgr:
		if mgr.fp_camera: mgr.fp_camera.fov = val
		if mgr.tp_camera: mgr.tp_camera.fov = val
	settings["camera_fov"] = val
	save_user_settings()

func _apply_preset(preset: String):
	match preset:
		"low":
			_set_control_value("msaa", 0)
			_set_control_value("shadow_resolution", 0)
			_set_control_value("render_scale", 0.75)
			_set_control_value("fog_density", 0.0)
		"medium":
			_set_control_value("msaa", 1)
			_set_control_value("shadow_resolution", 1)
			_set_control_value("render_scale", 1.0)
			_set_control_value("fog_density", 15.0)
		"high":
			_set_control_value("msaa", 2)
			_set_control_value("shadow_resolution", 2)
			_set_control_value("render_scale", 1.0)
			_set_control_value("fog_density", 30.0)
		"ultra":
			_set_control_value("msaa", 3)
			_set_control_value("shadow_resolution", 3)
			_set_control_value("render_scale", 1.0)
			_set_control_value("fog_density", 50.0)
	save_user_settings()

func _reset_graphics_defaults():
	_reset_setting("vsync")
	_reset_setting("window_mode")
	_reset_setting("msaa")
	_reset_setting("shadow_resolution")
	_reset_setting("fps_cap")
	_reset_setting("render_scale")
	_reset_setting("fog_density")

func _reset_physics_defaults():
	_reset_setting("hover_mode")
	_reset_setting("thrust_multiplier")
	_reset_setting("turn_sensitivity")
	_reset_setting("stabilize_force")
	_reset_setting("gravity_scale")
	_reset_setting("infinite_battery")

func _reset_env_defaults():
	_reset_setting("environment")
	_reset_setting("wind_preset")
	_reset_setting("light_energy")

func _reset_swarm_defaults():
	_reset_setting("swarm_active")
	_reset_setting("boid_count")
	_reset_setting("separation_radius")
	_reset_setting("boid_speed")
	_reset_setting("led_theme")

func _reset_audio_cam_defaults():
	_reset_setting("master_volume")
	_reset_setting("camera_mode")
	_reset_setting("camera_fov")

func _reset_defaults():
	_reset_graphics_defaults()
	_reset_physics_defaults()
	_reset_env_defaults()
	_reset_swarm_defaults()
	_reset_audio_cam_defaults()

func _get_player_drone() -> RigidBody3D:
	var scene = get_tree().current_scene
	if not scene: return null
	var mgr = scene.get_node_or_null("DroneControllerManager")
	if mgr and mgr.has_method("get_drone"):
		return mgr.get_drone()
	return scene.find_child("Drone", true, false) as RigidBody3D
