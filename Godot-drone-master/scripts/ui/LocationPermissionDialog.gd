# ============================================================================
# LocationPermissionDialog.gd - Godot UI Location Permission & Theme Welcome Screen
# ============================================================================
extends CanvasLayer

signal dialog_closed

static func create_dialog_node() -> CanvasLayer:
	var script = load("res://scripts/ui/LocationPermissionDialog.gd")
	var instance = CanvasLayer.new()
	instance.set_script(script)
	instance.layer = 150
	return instance

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()

func _build_ui() -> void:
	# Backdrop Dimmer
	var dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.75)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	
	# Center Container
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	# Main Dialog Panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 380)
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	
	var tm = get_node_or_null("/root/TranslationManager")

	# Header Title
	var title = Label.new()
	title.text = tm.get_auto_translation("PERM_TITLE") if tm else "WELCOME TO DRONE SIMULATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	vbox.add_child(title)
	
	# Clear Humanised Explanation Label
	var desc = Label.new()
	desc.text = tm.get_auto_translation("PERM_DESC") if tm else "The game can check your location to automatically match the UI theme with your local daylight and night time — giving you Light Mode during the day and Dark Mode at night.\n\nClick 'Allow Location Sync' to enable automatic location detection, or choose a theme below:"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Primary Choice 1: Allow Location Sync
	var btn_grant = Button.new()
	btn_grant.text = tm.get_auto_translation("BTN_ALLOW_SYNC") if tm else "Allow Location Sync"
	btn_grant.custom_minimum_size = Vector2(0, 40)
	btn_grant.pressed.connect(_on_grant_pressed)
	vbox.add_child(btn_grant)
	
	# Manual Theme Override Buttons (Light Mode & Dark Mode)
	var mode_hbox = HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(mode_hbox)
	
	var btn_light = Button.new()
	btn_light.text = tm.get_auto_translation("OPT_LIGHT_MODE") if tm else "Light Mode"
	btn_light.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_light.custom_minimum_size = Vector2(0, 36)
	btn_light.pressed.connect(func():
		var theme_mgr = get_node_or_null("/root/ThemeManager")
		if theme_mgr:
			theme_mgr.permission_state = "granted"
			theme_mgr.set_theme_mode("light")
		_close_dialog()
	)
	mode_hbox.add_child(btn_light)
	
	var btn_dark = Button.new()
	btn_dark.text = tm.get_auto_translation("OPT_DARK_MODE") if tm else "Dark Mode"
	btn_dark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_dark.custom_minimum_size = Vector2(0, 36)
	btn_dark.pressed.connect(func():
		var theme_mgr = get_node_or_null("/root/ThemeManager")
		if theme_mgr:
			theme_mgr.permission_state = "granted"
			theme_mgr.set_theme_mode("dark")
		_close_dialog()
	)
	mode_hbox.add_child(btn_dark)
	
	# City Selection Dropdown Option
	var city_box = HBoxContainer.new()
	city_box.add_theme_constant_override("separation", 8)
	vbox.add_child(city_box)
	
	var city_label = Label.new()
	city_label.text = tm.get_auto_translation("PERM_SELECT_CITY") if tm else "Or Select City:"
	city_label.add_theme_font_size_override("font_size", 12)
	city_box.add_child(city_label)
	
	var city_dropdown = OptionButton.new()
	city_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var cities = theme_mgr.PRESET_CITIES if theme_mgr else []
	for i in range(cities.size()):
		city_dropdown.add_item("%s, %s" % [cities[i]["name"], cities[i]["country"]], i)
	city_dropdown.item_selected.connect(_on_city_selected)
	city_box.add_child(city_dropdown)
	
	# Confirm & Continue Button
	var btn_confirm = Button.new()
	btn_confirm.text = tm.get_auto_translation("BTN_CONFIRM_CONTINUE") if tm else "Confirm & Continue"
	btn_confirm.custom_minimum_size = Vector2(0, 38)
	btn_confirm.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm:
			if tm.permission_state == "prompt":
				tm.permission_state = "granted"
			tm.save_config()
		_close_dialog()
	)
	vbox.add_child(btn_confirm)

	# Apply initial theme styling to modal
	if theme_mgr:
		theme_mgr.apply_theme_to_control(panel)

func _on_grant_pressed() -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr:
		theme_mgr.permission_state = "granted"
		theme_mgr.set_theme_mode("auto")
		theme_mgr.request_ip_geolocation()
	_close_dialog()

func _on_city_selected(index: int) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr and index >= 0 and index < theme_mgr.PRESET_CITIES.size():
		var city = theme_mgr.PRESET_CITIES[index]
		theme_mgr.set_custom_location(city["name"], city["lat"], city["lng"])

func _close_dialog() -> void:
	dialog_closed.emit()
	queue_free()
