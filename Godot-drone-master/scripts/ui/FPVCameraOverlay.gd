extends CanvasLayer
class_name FPVCameraOverlay

## Real-Life FPV Drone Camera Vision & OSD Overlay
## Displays ONLY when the single player drone is in First Person View (FPV).
## Styled in light blue / cyan matching the simulator menu.
## ALL UI elements are cleanly positioned on the RIGHT side of the screen.

var fpv_active: bool = false
var target_drone: Node = null

var _vignette_rect: ColorRect
var _osd_container: Control
var _top_right_label: Label
var _mid_right_label: Label
var _bottom_right_label: Label
var _center_reticle: Control

var _timer: float = 0.0

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr:
		theme_mgr.theme_changed.connect(_on_theme_changed)
		_on_theme_changed(theme_mgr.current_ui_theme)

func _on_theme_changed(_new_theme: String) -> void:
	# Exact signature cyan OSD color matching ALT/SPD OSD text
	var osd_color = Color(0.20, 0.85, 1.0, 0.95)
	
	if _top_right_label: _top_right_label.add_theme_color_override("font_color", osd_color)
	if _mid_right_label: _mid_right_label.add_theme_color_override("font_color", osd_color)
	if _bottom_right_label: _bottom_right_label.add_theme_color_override("font_color", osd_color)
	
	var reticle_label = get_node_or_null("FPVRoot/OSDContainer/CenterReticle/ReticleCross")
	if reticle_label:
		reticle_label.add_theme_color_override("font_color", osd_color)
		reticle_label.remove_theme_color_override("font_outline_color")
		reticle_label.remove_theme_constant_override("outline_size")

func _build_ui() -> void:
	# Fullscreen container - MOUSE_FILTER_IGNORE ensures clicks pass through to UI menus
	var root = Control.new()
	root.name = "FPVRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)

	# 1. Vignette & Lens Edge Overlay (Darkened curved corners of FPV wide lens)
	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "LensVignette"
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.anchor_right = 1.0
	_vignette_rect.anchor_bottom = 1.0
	_vignette_rect.color = Color(0, 0, 0, 0.12)
	root.add_child(_vignette_rect)

	# 2. OSD Container
	_osd_container = Control.new()
	_osd_container.name = "OSDContainer"
	_osd_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_osd_container.anchor_right = 1.0
	_osd_container.anchor_bottom = 1.0
	root.add_child(_osd_container)

	# Signature light blue / cyan menu theme color
	var osd_color = Color(0.2, 0.85, 1.0, 0.95)
	var font_size = 15

	# Top-Right OSD (System Status, MAVLink & Primary Battery HUD) - Positioned on right side
	_top_right_label = Label.new()
	_top_right_label.name = "TopRightOSD"
	_top_right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_right_label.anchor_left = 1.0
	_top_right_label.anchor_right = 1.0
	_top_right_label.offset_left = -310
	_top_right_label.offset_top = 25
	_top_right_label.add_theme_font_size_override("font_size", font_size)
	_top_right_label.add_theme_color_override("font_color", osd_color)
	_top_right_label.text = "DRONE-01  MAVLINK 99%\n[⚡] BATTERY 100% (4.20V/C)\nFLIGHT TIME: ~20 MIN"
	_osd_container.add_child(_top_right_label)

	# Middle-Right OSD (Altitude, Speed & Flight Mode) - Positioned on right edge
	_mid_right_label = Label.new()
	_mid_right_label.name = "MidRightOSD"
	_mid_right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mid_right_label.anchor_left = 1.0
	_mid_right_label.anchor_right = 1.0
	_mid_right_label.anchor_top = 0.5
	_mid_right_label.anchor_bottom = 0.5
	_mid_right_label.offset_left = -310
	_mid_right_label.offset_top = -30
	_mid_right_label.add_theme_font_size_override("font_size", font_size)
	_mid_right_label.add_theme_color_override("font_color", osd_color)
	_mid_right_label.text = "ALT: 0.0 m\nSPD: 0.0 m/s\nMODE: ACRO / AIRMODE"
	_osd_container.add_child(_mid_right_label)

	# Bottom-Right OSD (Throttle Output) - Positioned on bottom-right corner
	_bottom_right_label = Label.new()
	_bottom_right_label.name = "BottomRightOSD"
	_bottom_right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_right_label.anchor_left = 1.0
	_bottom_right_label.anchor_right = 1.0
	_bottom_right_label.anchor_top = 1.0
	_bottom_right_label.anchor_bottom = 1.0
	_bottom_right_label.offset_left = -310
	_bottom_right_label.offset_top = -50
	_bottom_right_label.add_theme_font_size_override("font_size", font_size)
	_bottom_right_label.add_theme_color_override("font_color", osd_color)
	_bottom_right_label.text = "THROTTLE: 0%"
	_osd_container.add_child(_bottom_right_label)

	# Center Crosshair & Horizon Pitch Reticle [ + ]
	_center_reticle = Control.new()
	_center_reticle.name = "CenterReticle"
	_center_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_reticle.anchor_left = 0.5
	_center_reticle.anchor_right = 0.5
	_center_reticle.anchor_top = 0.5
	_center_reticle.anchor_bottom = 0.5
	_osd_container.add_child(_center_reticle)

	var reticle_label = Label.new()
	reticle_label.name = "ReticleCross"
	reticle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle_label.anchor_left = 0.5
	reticle_label.anchor_right = 0.5
	reticle_label.anchor_top = 0.5
	reticle_label.anchor_bottom = 0.5
	reticle_label.offset_left = -20
	reticle_label.offset_top = -12
	reticle_label.add_theme_font_size_override("font_size", 18)
	reticle_label.add_theme_color_override("font_color", osd_color)
	reticle_label.text = "[ + ]"
	_center_reticle.add_child(reticle_label)

func set_fpv_active(active: bool) -> void:
	fpv_active = active
	visible = fpv_active and not (get_tree() and get_tree().paused)

func set_target_drone(drone: Node) -> void:
	target_drone = drone

func _process(delta: float) -> void:
	if not fpv_active or not is_inside_tree():
		return

	if get_tree() and get_tree().paused:
		visible = false
		return
	else:
		visible = fpv_active

	_timer += delta

	# Dynamic target drone resolution if null
	if target_drone == null or not is_instance_valid(target_drone) or not target_drone.is_inside_tree():
		var main_scene = get_tree().current_scene if get_tree() else null
		if main_scene:
			var manager = main_scene.get_node_or_null("DroneControllerManager")
			if not manager or not manager.get("drone"):
				manager = main_scene.get_node_or_null("SingleDroneController")
			if manager and "drone" in manager and manager.drone and is_instance_valid(manager.drone):
				target_drone = manager.drone
			elif main_scene.find_child("Drone", true, false):
				target_drone = main_scene.find_child("Drone", true, false)

	# Update live telemetry from target drone if valid
	var alt = 0.0
	var spd = 0.0
	var bat_percent = 100.0
	var thr_percent = 0

	if target_drone and is_instance_valid(target_drone) and target_drone.is_inside_tree():
		alt = target_drone.global_position.y
		if target_drone is RigidBody3D:
			spd = target_drone.linear_velocity.length()

		var d_node = target_drone
		if d_node.get("drone") and is_instance_valid(d_node.drone):
			d_node = d_node.drone
		if d_node.has_method("get_battery_percent"):
			bat_percent = d_node.get_battery_percent()
		elif "battery_percent" in d_node and d_node.battery_percent != null:
			bat_percent = float(d_node.battery_percent)
		elif d_node.get("battery_manager") and is_instance_valid(d_node.battery_manager):
			bat_percent = d_node.battery_manager.battery_percent

		if target_drone.get("smoothed_input") != null:
			var sm_in = target_drone.smoothed_input
			if sm_in is Vector4:
				thr_percent = int(clampf(sm_in.x * 100.0, 0.0, 100.0))

	var bat_v = 13.2 + (bat_percent / 100.0) * 3.6
	var cell_v = bat_v / 4.0
	var flight_mins = int(bat_percent * 0.2)

	_top_right_label.text = "DRONE-01  MAVLINK 99%\n[⚡] BATTERY " + str(int(bat_percent)) + "% (" + str(snappedf(cell_v, 0.01)) + "V/C)\nFLIGHT TIME: ~" + str(flight_mins) + " MIN"
	_mid_right_label.text = "ALT: " + str(snappedf(maxf(alt, 0.0), 0.1)) + " m\nSPD: " + str(snappedf(spd, 0.1)) + " m/s\nMODE: ACRO / AIRMODE"
	_bottom_right_label.text = "THROTTLE: " + str(thr_percent) + "%"

	# Light Blue / Cyan menu glow pulse
	var osd_color = Color(0.2, 0.85, 1.0, 0.88 + 0.08 * sin(_timer * 3.0))
	_top_right_label.add_theme_color_override("font_color", osd_color)
	_mid_right_label.add_theme_color_override("font_color", osd_color)
	_bottom_right_label.add_theme_color_override("font_color", osd_color)
