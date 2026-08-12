# ============================================================================
# ThemeManager.gd - Godot 4.6 Central UI Theme & Location Sync Manager
# ============================================================================
extends Node

signal theme_changed(new_theme: String)
signal location_updated(city: String, lat: float, lng: float)
signal permission_changed(new_permission: String)

const CONFIG_FILE_PATH = "user://drone_sim_settings.cfg"

# State
var theme_mode: String = "auto"       # "auto" | "light" | "dark"
var current_ui_theme: String = "dark" # "light" | "dark"
var permission_state: String = "prompt" # "prompt" | "granted" | "denied" | "custom"

var user_lat: float = 13.7563        # Default fallback: Bangkok, Thailand coordinates
var user_lng: float = 100.5018
var city_name: String = "Detecting Location..."
var country_name: String = ""

var http_req: HTTPRequest = null
var dialog_instance: CanvasLayer = null

# Popular Global Cities for Manual Selection (No Duplicate Countries, No Emojis)
const PRESET_CITIES = [
	{"name": "Bangkok", "country": "Thailand", "lat": 13.7563, "lng": 100.5018},
	{"name": "Tokyo", "country": "Japan", "lat": 35.6762, "lng": 139.6503},
	{"name": "Sydney", "country": "Australia", "lat": -33.8688, "lng": 151.2093},
	{"name": "Dubai", "country": "United Arab Emirates", "lat": 25.2048, "lng": 55.2708},
	{"name": "Singapore", "country": "Singapore", "lat": 1.3521, "lng": 103.8198},
	{"name": "London", "country": "United Kingdom", "lat": 51.5074, "lng": -0.1278},
	{"name": "Paris", "country": "France", "lat": 48.8566, "lng": 2.3522},
	{"name": "Berlin", "country": "Germany", "lat": 52.5200, "lng": 13.4050},
	{"name": "Cairo", "country": "Egypt", "lat": 30.0444, "lng": 31.2357},
	{"name": "New York", "country": "United States", "lat": 40.7128, "lng": -74.0060},
	{"name": "Los Angeles", "country": "United States", "lat": 34.0522, "lng": -118.2437},
	{"name": "Rio de Janeiro", "country": "Brazil", "lat": -22.9068, "lng": -43.1729},
	{"name": "Reykjavik", "country": "Iceland", "lat": 64.1466, "lng": -21.9426}
]

var _check_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	reevaluate_theme()
	
	if permission_state == "prompt":
		call_deferred("prompt_location_permission")
	else:
		call_deferred("request_ip_geolocation")

func _process(delta: float) -> void:
	if theme_mode == "auto":
		_check_timer += delta
		if _check_timer >= 30.0:
			_check_timer = 0.0
			reevaluate_theme()

func _load_config() -> void:
	var config = ConfigFile.new()
	if config.load(CONFIG_FILE_PATH) == OK:
		if config.has_section_key("ui_theme", "theme_mode"):
			theme_mode = config.get_value("ui_theme", "theme_mode", "auto")
		if config.has_section_key("ui_theme", "permission_state"):
			permission_state = config.get_value("ui_theme", "permission_state", "prompt")
		if config.has_section_key("ui_theme", "user_lat"):
			user_lat = config.get_value("ui_theme", "user_lat", 12.9236)
		if config.has_section_key("ui_theme", "user_lng"):
			user_lng = config.get_value("ui_theme", "user_lng", 100.8825)
		if config.has_section_key("ui_theme", "city_name"):
			city_name = config.get_value("ui_theme", "city_name", "Bangkok")

func save_config() -> void:
	var config = ConfigFile.new()
	config.load(CONFIG_FILE_PATH)
	config.set_value("ui_theme", "theme_mode", theme_mode)
	config.set_value("ui_theme", "permission_state", permission_state)
	config.set_value("ui_theme", "user_lat", user_lat)
	config.set_value("ui_theme", "user_lng", user_lng)
	config.set_value("ui_theme", "city_name", city_name)
	config.save(CONFIG_FILE_PATH)

# ============================================================================
# THEME SETTINGS & EVALUATION
# ============================================================================
func set_theme_mode(mode: String) -> void:
	if mode in ["auto", "light", "dark"]:
		theme_mode = mode
		save_config()
		reevaluate_theme()

func reevaluate_theme() -> void:
	var target_theme = "dark"
	
	if theme_mode == "light":
		target_theme = "light"
	elif theme_mode == "dark":
		target_theme = "dark"
	else: # "auto"
		if is_daytime_at_location(user_lat, user_lng):
			target_theme = "light"
		else:
			target_theme = "dark"
	
	current_ui_theme = target_theme
	apply_theme_globally()
	theme_changed.emit(current_ui_theme)

func is_daytime_at_location(lat: float, lng: float) -> bool:
	# Get UTC time dict for precision astronomical calculation
	var utc_time = Time.get_time_dict_from_system(true)
	var utc_date = Time.get_date_dict_from_system(true)
	var local_time = Time.get_time_dict_from_system(false)
	
	var hour_utc = utc_time["hour"] + utc_time["minute"] / 60.0
	
	# Day of year calculation
	var day_of_year = _get_day_of_year(utc_date["year"], utc_date["month"], utc_date["day"])
	var declination = 23.45 * sin(deg_to_rad(360.0 / 365.0 * (284.0 + day_of_year)))
	
	var lat_rad = deg_to_rad(lat)
	var dec_rad = deg_to_rad(declination)
	
	var cos_hour_angle = -tan(lat_rad) * tan(dec_rad)
	cos_hour_angle = clamp(cos_hour_angle, -1.0, 1.0)
	var half_day_hours = rad_to_deg(acos(cos_hour_angle)) / 15.0
	
	# Solar noon in UTC hours
	var solar_noon_utc = 12.0 - (lng / 15.0)
	while solar_noon_utc < 0.0: solar_noon_utc += 24.0
	while solar_noon_utc >= 24.0: solar_noon_utc -= 24.0
	
	var sunrise_utc = _normalize_hour(solar_noon_utc - half_day_hours)
	var sunset_utc = _normalize_hour(solar_noon_utc + half_day_hours)
	
	if sunrise_utc < sunset_utc:
		if hour_utc >= sunrise_utc and hour_utc <= sunset_utc:
			return true
	else:
		if hour_utc >= sunrise_utc or hour_utc <= sunset_utc:
			return true
			
	# Fallback check using local system hour (06:00 to 18:30)
	var local_hour = local_time["hour"] + local_time["minute"] / 60.0
	return local_hour >= 6.0 and local_hour <= 18.5

func _normalize_hour(h: float) -> float:
	var res = h
	while res < 0.0: res += 24.0
	while res >= 24.0: res -= 24.0
	return res

func _get_day_of_year(y: int, m: int, d: int) -> int:
	var days_in_months = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0):
		days_in_months[2] = 29
	var day_count = d
	for i in range(1, m):
		day_count += days_in_months[i]
	return day_count

# ============================================================================
# LOCATION & GEOLOCATION API REQUEST
# ============================================================================
func prompt_location_permission() -> void:
	if dialog_instance and is_instance_valid(dialog_instance):
		return
		
	var dialog_script = load("res://scripts/ui/LocationPermissionDialog.gd")
	if dialog_script:
		dialog_instance = dialog_script.create_dialog_node()
		add_child(dialog_instance)

func request_ip_geolocation() -> void:
	if not http_req or not is_instance_valid(http_req):
		http_req = HTTPRequest.new()
		add_child(http_req)
		http_req.request_completed.connect(_on_geolocation_response)
		
	http_req.request("http://ip-api.com/json/")

func _on_geolocation_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			var data = json.get_data()
			if data is Dictionary and data.get("status") == "success":
				user_lat = data.get("lat", 13.7563)
				user_lng = data.get("lon", 100.5018)
				city_name = data.get("city", "Bangkok")
				country_name = data.get("country", "Thailand")
				permission_state = "granted"
				
				save_config()
				location_updated.emit("%s, %s" % [city_name, country_name], user_lat, user_lng)
				reevaluate_theme()
				return
	
	# Fallback if network request fails
	if city_name == "Detecting Location...":
		city_name = "Bangkok"
		country_name = "Thailand"
	location_updated.emit("%s, %s" % [city_name, country_name], user_lat, user_lng)
	reevaluate_theme()

func set_custom_location(c_name: String, lat: float, lng: float) -> void:
	city_name = c_name
	user_lat = lat
	user_lng = lng
	permission_state = "custom"
	save_config()
	permission_changed.emit(permission_state)
	location_updated.emit(city_name, user_lat, user_lng)
	reevaluate_theme()

# ============================================================================
# RECURSIVE GODOT UI THEME STYLING ENGINE (REFINED LIGHT & DARK PALETTES)
# ============================================================================
func apply_theme_globally() -> void:
	var tree = get_tree()
	if not tree or not tree.root:
		return
	_apply_theme_recursive(tree.root)

func apply_theme_to_control(root_control: Control) -> void:
	_apply_theme_recursive(root_control)

func _apply_theme_recursive(node: Node) -> void:
	if not node:
		return
	if node is FPVCameraOverlay or node.name == "FPVRoot" or node.name == "OSDContainer" or node.name == "CenterReticle":
		return
		
	if node is Control:
		_style_single_control(node as Control)
		
	for child in node.get_children():
		_apply_theme_recursive(child)

func _style_single_control(ctrl: Control) -> void:
	var is_light = (current_ui_theme == "light")
	
	if ctrl is PanelContainer or ctrl is Panel:
		var parent_ctrl = ctrl.get_parent()
		var is_nested = (parent_ctrl is PanelContainer or parent_ctrl is Panel or ctrl.name == "ContentStack" or ctrl.has_meta("frameless"))
		
		var style = StyleBoxFlat.new()
		if is_nested:
			style.set_border_width_all(0)
			style.bg_color = Color(0, 0, 0, 0)
			style.shadow_size = 0
		else:
			style.set_border_width_all(1)
			style.corner_radius_top_left = 12
			style.corner_radius_top_right = 12
			style.corner_radius_bottom_left = 12
			style.corner_radius_bottom_right = 12
			
			if is_light:
				# Highly refined frosted light glass design
				style.bg_color = Color(0.88, 0.91, 0.95, 0.94)
				style.border_color = Color(0.12, 0.45, 0.80, 0.75)
				style.shadow_color = Color(0.05, 0.10, 0.20, 0.12)
				style.shadow_size = 6
			else:
				# Refined midnight dark glass design
				style.bg_color = Color(0.06, 0.09, 0.16, 0.94)
				style.border_color = Color(0.20, 0.85, 1.0, 0.6)
				style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
				style.shadow_size = 8
			
		ctrl.add_theme_stylebox_override("panel", style)
		
	elif ctrl is Button:
		var btn = ctrl as Button
		var normal_style = StyleBoxFlat.new()
		normal_style.set_border_width_all(1)
		normal_style.corner_radius_top_left = 8
		normal_style.corner_radius_top_right = 8
		normal_style.corner_radius_bottom_left = 8
		normal_style.corner_radius_bottom_right = 8
		normal_style.content_margin_left = 12
		normal_style.content_margin_right = 12
		normal_style.content_margin_top = 6
		normal_style.content_margin_bottom = 6
		
		var hover_style = normal_style.duplicate() as StyleBoxFlat
		var focus_style = normal_style.duplicate() as StyleBoxFlat
		var disabled_style = normal_style.duplicate() as StyleBoxFlat

		var is_danger = (btn.name.containsn("quit") or btn.name.containsn("power") or btn.text.containsn("quit") or btn.text.containsn("power off") or btn.has_meta("danger"))

		if is_danger:
			normal_style.bg_color = Color(0.72, 0.12, 0.12, 0.95)
			normal_style.border_color = Color(0.90, 0.25, 0.25, 1.0)
			normal_style.set_border_width_all(2)

			hover_style.bg_color = Color(0.88, 0.18, 0.18, 1.0)
			hover_style.border_color = Color(1.0, 0.40, 0.40, 1.0)
			hover_style.set_border_width_all(2)

			focus_style.bg_color = Color(0.78, 0.14, 0.14, 0.98)
			focus_style.border_color = Color(1.0, 0.50, 0.50, 1.0)
			focus_style.set_border_width_all(2)

			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
			btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
		elif is_light:
			normal_style.bg_color = Color(0.80, 0.85, 0.92, 0.95)
			normal_style.border_color = Color(0.20, 0.50, 0.85, 0.6)
			btn.add_theme_color_override("font_color", Color(0.06, 0.10, 0.18, 1.0))
			btn.add_theme_color_override("font_focus_color", Color(0.06, 0.10, 0.18, 1.0))
			
			hover_style.bg_color = Color(0.12, 0.48, 0.88, 1.0)
			hover_style.border_color = Color(0.20, 0.65, 1.0, 1.0)
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

			focus_style.bg_color = Color(0.82, 0.88, 0.96, 0.95)
			focus_style.border_color = Color(0.12, 0.48, 0.88, 1.0)
			focus_style.set_border_width_all(2)

			disabled_style.bg_color = Color(0.85, 0.88, 0.92, 0.85)
			disabled_style.border_color = Color(0.70, 0.76, 0.84, 0.6)
			btn.add_theme_color_override("font_disabled_color", Color(0.48, 0.54, 0.62, 0.8))
		else:
			normal_style.bg_color = Color(0.12, 0.16, 0.25, 0.95)
			normal_style.border_color = Color(0.20, 0.85, 1.0, 0.4)
			btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
			btn.add_theme_color_override("font_focus_color", Color(0.92, 0.96, 1.0, 1.0))
			
			hover_style.bg_color = Color(0.20, 0.65, 0.95, 0.9)
			hover_style.border_color = Color(0.20, 0.85, 1.0, 1.0)
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

			focus_style.bg_color = Color(0.12, 0.18, 0.30, 0.95)
			focus_style.border_color = Color(0.20, 0.85, 1.0, 1.0)
			focus_style.set_border_width_all(2)

			disabled_style.bg_color = Color(0.10, 0.12, 0.18, 0.6)
			disabled_style.border_color = Color(0.20, 0.35, 0.50, 0.4)
			btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.52, 0.60, 0.6))
			
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.add_theme_stylebox_override("focus", focus_style)
		btn.add_theme_stylebox_override("disabled", disabled_style)
		
	elif ctrl is Slider:
		var slider = ctrl as Slider
		var track_style = StyleBoxFlat.new()
		track_style.corner_radius_top_left = 4
		track_style.corner_radius_top_right = 4
		track_style.corner_radius_bottom_left = 4
		track_style.corner_radius_bottom_right = 4
		track_style.content_margin_top = 4
		track_style.content_margin_bottom = 4
		
		var filled_style = track_style.duplicate() as StyleBoxFlat

		if is_light:
			# Unfilled background track: soft light slate
			track_style.bg_color = Color(0.78, 0.83, 0.90, 0.95)
			track_style.border_color = Color(0.65, 0.72, 0.82, 0.5)
			track_style.set_border_width_all(1)

			# Filled active track: RICH DARK COBALT / NAVY BLUE
			filled_style.bg_color = Color(0.10, 0.40, 0.82, 1.0)
			filled_style.border_color = Color(0.08, 0.32, 0.70, 0.8)
			filled_style.set_border_width_all(1)
		else:
			# Unfilled background track: dark slate
			track_style.bg_color = Color(0.12, 0.16, 0.24, 0.95)
			track_style.border_color = Color(0.20, 0.65, 0.90, 0.4)
			track_style.set_border_width_all(1)

			# Filled active track: bright cyan
			filled_style.bg_color = Color(0.20, 0.75, 1.0, 1.0)
			filled_style.border_color = Color(0.40, 0.85, 1.0, 0.9)
			filled_style.set_border_width_all(1)

		slider.add_theme_stylebox_override("slider", track_style)
		slider.add_theme_stylebox_override("grabber_area", filled_style)
		slider.add_theme_stylebox_override("grabber_area_highlight", filled_style)

		# Explicit Grabber Icons: Unhovered = 100% SOLID OPAQUE OBJECT | Hovered = SEE-THROUGH TRANSLUCENT GLASS
		slider.add_theme_icon_override("grabber", _create_circle_grabber_texture(false, is_light))
		slider.add_theme_icon_override("grabber_highlight", _create_circle_grabber_texture(true, is_light))

	elif ctrl is ProgressBar:
		var pb = ctrl as ProgressBar
		var bg_style = StyleBoxFlat.new()
		bg_style.set_border_width_all(1)
		bg_style.corner_radius_top_left = 6
		bg_style.corner_radius_top_right = 6
		bg_style.corner_radius_bottom_left = 6
		bg_style.corner_radius_bottom_right = 6

		var fill_style = bg_style.duplicate() as StyleBoxFlat

		if is_light:
			bg_style.bg_color = Color(0.78, 0.83, 0.90, 0.95)
			bg_style.border_color = Color(0.65, 0.72, 0.82, 0.5)

			fill_style.bg_color = Color(0.10, 0.40, 0.82, 1.0)
			fill_style.border_color = Color(0.08, 0.32, 0.70, 0.8)
			pb.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		else:
			bg_style.bg_color = Color(0.12, 0.16, 0.24, 0.95)
			bg_style.border_color = Color(0.20, 0.65, 0.90, 0.4)

			fill_style.bg_color = Color(0.20, 0.75, 1.0, 1.0)
			fill_style.border_color = Color(0.40, 0.85, 1.0, 0.9)
			pb.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

		pb.add_theme_stylebox_override("background", bg_style)
		pb.add_theme_stylebox_override("fill", fill_style)

	elif ctrl is CheckButton or ctrl is CheckBox:
		var cb = ctrl as Button
		if is_light:
			cb.add_theme_color_override("font_color", Color(0.06, 0.10, 0.18, 1.0))
			cb.add_theme_color_override("font_pressed_color", Color(0.10, 0.40, 0.82, 1.0))
			cb.add_theme_color_override("font_hover_color", Color(0.12, 0.48, 0.88, 1.0))
		else:
			cb.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
			cb.add_theme_color_override("font_pressed_color", Color(0.20, 0.75, 1.0, 1.0))
			cb.add_theme_color_override("font_hover_color", Color(0.40, 0.85, 1.0, 1.0))

	elif ctrl is LineEdit:
		var le = ctrl as LineEdit
		var style = StyleBoxFlat.new()
		style.set_border_width_all(1)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4

		if is_light:
			style.bg_color = Color(0.96, 0.98, 1.0, 0.95)
			style.border_color = Color(0.20, 0.55, 0.90, 0.6)
			le.add_theme_color_override("font_color", Color(0.06, 0.12, 0.22, 1.0))
			le.add_theme_color_override("font_placeholder_color", Color(0.45, 0.52, 0.60, 0.7))
			le.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0, 1.0))
			le.add_theme_color_override("selection_color", Color(0.12, 0.48, 0.88, 0.8))
		else:
			style.bg_color = Color(0.10, 0.14, 0.22, 0.95)
			style.border_color = Color(0.20, 0.75, 1.0, 0.5)
			le.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
			le.add_theme_color_override("font_placeholder_color", Color(0.55, 0.65, 0.75, 0.6))
			le.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0, 1.0))
			le.add_theme_color_override("selection_color", Color(0.20, 0.65, 0.95, 0.8))

		le.add_theme_stylebox_override("normal", style)
		le.add_theme_stylebox_override("focus", style)

	elif ctrl is SpinBox:
		var sb = ctrl as SpinBox
		var le = sb.get_line_edit()
		if le:
			_style_single_control(le)

	elif ctrl is Label:
		var lbl = ctrl as Label
		var has_style = lbl.has_theme_stylebox_override("normal")
		if is_light:
			lbl.add_theme_color_override("font_color", Color(0.06, 0.10, 0.18, 1.0))
			if lbl.has_theme_color_override("font_outline_color"):
				lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.9))
			if has_style:
				var sb = lbl.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
				if sb:
					sb.bg_color = Color(0.85, 0.90, 0.96, 0.95)
					sb.border_color = Color(0.65, 0.78, 0.90, 0.7)
					sb.set_border_width_all(1)
					lbl.add_theme_stylebox_override("normal", sb)
		else:
			lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
			if has_style:
				var sb = lbl.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
				if sb:
					sb.bg_color = Color(0.12, 0.16, 0.24, 0.85)
					sb.border_color = Color(0.20, 0.65, 0.90, 0.4)
					sb.set_border_width_all(1)
					lbl.add_theme_stylebox_override("normal", sb)

func _create_circle_grabber_texture(is_hovered: bool, is_light: bool) -> Texture2D:
	var size = 20
	var img = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var outer_radius = 9.0
	var border_width = 2.2
	var inner_radius = outer_radius - border_width
	
	var fill_color: Color
	var border_color: Color
	
	if is_light:
		border_color = Color(0.10, 0.40, 0.82, 1.0)
		if is_hovered:
			# Hovered / Selected: SEE-THROUGH TRANSLUCENT GLASS (35% alpha fill)
			fill_color = Color(1.0, 1.0, 1.0, 0.35)
		else:
			# Unhovered (Normal): 100% FULLY OPAQUE SOLID WHITE (1.0 alpha fill!)
			fill_color = Color(1.0, 1.0, 1.0, 1.0)
	else:
		border_color = Color(0.20, 0.75, 1.0, 1.0)
		if is_hovered:
			# Hovered / Selected: SEE-THROUGH TRANSLUCENT GLASS
			fill_color = Color(0.20, 0.75, 1.0, 0.35)
		else:
			# Unhovered (Normal): 100% FULLY OPAQUE SOLID CYAN-WHITE
			fill_color = Color(0.92, 0.96, 1.0, 1.0)

	for y in range(size):
		for x in range(size):
			var pos = Vector2(x + 0.5, y + 0.5)
			var dist = pos.distance_to(center)
			
			# Sub-pixel anti-aliased outer edge smoothing
			var outer_alpha = clampf(outer_radius + 0.5 - dist, 0.0, 1.0)
			if outer_alpha <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			# Sub-pixel smooth border to fill transition
			var border_alpha = clampf(dist - inner_radius + 0.5, 0.0, 1.0)
			var pixel_color = fill_color.lerp(border_color, border_alpha)
			pixel_color.a *= outer_alpha
			
			img.set_pixel(x, y, pixel_color)
				
	return ImageTexture.create_from_image(img)
